#!/usr/bin/env bash
# validate-generated.sh — correctness gate for a project the justfile-template
# skill has just scaffolded and populated. This is an LLM-run check (NOT a `just`
# recipe, NOT copied into the target). It mirrors scripts/validate.sh but points
# at the GENERATED project and additionally fails on leftover `# TODO` markers.
#
#   validate-generated.sh <TARGET_DIR>
#
# Exits non-zero with a concrete, greppable error list so the skill can fix and
# re-run until it passes.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

TARGET="${1:-}"
[ -n "$TARGET" ] || die "usage: validate-generated.sh <TARGET_DIR>"
[ -d "$TARGET" ] || die "not a directory: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"
{ [ -f "$TARGET/Justfile" ] && [ -d "$TARGET/.just" ]; } \
    || die "not a generated project (missing Justfile or .just/): $TARGET"

T="$TARGET"; J="$TARGET/.just"
errors=0
fail() { err "$*"; errors=$((errors + 1)); }

info "Validating generated project: $T"

# --- 1. Required files exist (mobile/desktop are optional mod?, checked via refs)
info "Checking required files"
required_files=(
    "Justfile"
    ".just/modules/project.just"
    ".just/modules/config.just"
    ".just/modules/db.just"
    ".just/modules/tests.just"
    ".just/modules/reports.just"
    ".just/manifests/commands.tsv"
    ".just/manifests/tools.tsv"
    ".just/manifests/platforms.tsv"
    ".just/manifests/pending.tsv"
    ".just/manifests/env.required"
    ".just/scripts/unix/lib.sh"
    ".just/scripts/unix/pending.sh"
    ".just/adapters/arch.sh"
    ".just/adapters/debian.sh"
    ".just/adapters/macos.sh"
    ".just/adapters/windows.ps1"
)
for f in "${required_files[@]}"; do
    if [ -e "$T/$f" ]; then ok "$f"; else fail "missing: $f"; fi
done

# --- 2. Cross-references (Justfile -> modules) -----------------------------
# import / mod require the target; import? / mod? are optional (absence is fine).
info "Checking references (Justfile -> modules)"
while IFS= read -r m; do
    [ -n "$m" ] || continue
    kw="${m%%[[:space:]]*}"
    path="$(printf '%s' "$m" | grep -oE "'[^']+'" | tr -d "'")"
    [ -n "$path" ] || continue
    if [ -f "$T/$path" ]; then
        ok "ref -> $path"
    elif [ "${kw%\?}" != "$kw" ]; then
        warn "optional module absent (ok): $path"
    else
        fail "required import/mod target missing: $path"
    fi
done < <(grep -oE "(import\??|mod\??)[[:space:]]+[^']*'[^']+'" "$T/Justfile")

info "Checking references (modules -> scripts)"
while read -r base; do
    [ -n "$base" ] || continue
    if [ -f "$J/scripts/unix/$base" ] || [ -f "$J/scripts/windows/$base" ]; then
        ok "script -> $base"
    else
        fail "referenced script missing: $base"
    fi
done < <(grep -rhoE '[A-Za-z0-9_-]+\.(sh|ps1)' "$J/modules" | sort -u)

# --- 3. TSV column counts --------------------------------------------------
info "Checking TSV column counts"
check_tsv_cols() {
    local file="$1" want="$2" line n=0 bad=0
    [ -f "$file" ] || { fail "missing TSV: ${file#"$T/"}"; return; }
    while IFS= read -r line; do
        n=$((n + 1))
        [ -n "$line" ] || continue
        case "$line" in \#*) continue ;; esac
        local cols; cols=$(awk -F'\t' '{print NF}' <<< "$line")
        if [ "$cols" -ne "$want" ]; then fail "${file#"$T/"} line $n has $cols columns (want $want)"; bad=1; fi
    done < "$file"
    [ "$bad" -eq 0 ] && ok "$(basename "$file"): $want columns"
}
check_tsv_cols "$J/manifests/tools.tsv" 8
check_tsv_cols "$J/manifests/commands.tsv" 5
check_tsv_cols "$J/manifests/platforms.tsv" 5
check_tsv_cols "$J/manifests/pending.tsv" 3

# --- 4. Platform order Arch -> Debian -> macOS -> Windows ------------------
info "Checking platform order"
tools_hdr=$(head -1 "$J/manifests/tools.tsv" 2>/dev/null || true)
if [ "$(cut -f2-5 <<< "$tools_hdr")" = "$(printf 'arch\tdebian\tmacos\twindows')" ]; then
    ok "tools.tsv columns ordered arch,debian,macos,windows"
else
    fail "tools.tsv columns not in order arch,debian,macos,windows: $(cut -f2-5 <<< "$tools_hdr")"
fi
plat_order=$(tsv_rows "$J/manifests/platforms.tsv" | cut -f1 | paste -sd, -)
if [ "$plat_order" = "arch,debian,macos,windows" ]; then
    ok "platforms.tsv rows ordered arch,debian,macos,windows"
else
    fail "platforms.tsv rows not in order: $plat_order"
fi

# --- 5. Leftover # TODO placeholders (the whole point of populating) -------
info "Checking for leftover # TODO placeholders"
todo_hits=$(grep -rnE '#[[:space:]]*TODO' --include='*.sh' "$J/scripts/unix" "$J/adapters" 2>/dev/null || true)
if [ -n "$todo_hits" ]; then
    while IFS= read -r line; do
        [ -n "$line" ] && fail "leftover TODO: ${line#"$T/"}"
    done <<< "$todo_hits"
    err "  -> replace every '# TODO' with the real command, or mark the recipe as intentionally disabled."
else
    ok "no leftover # TODO placeholders"
fi

# --- 6. Bash syntax --------------------------------------------------------
info "Checking Bash syntax (bash -n)"
sh_bad=0
while read -r sh; do
    if bash -n "$sh" 2>/dev/null; then :; else fail "bash -n failed: ${sh#"$T/"}"; sh_bad=1; fi
done < <(find "$J" -name '*.sh' -type f | sort)
[ "$sh_bad" -eq 0 ] && ok "all Bash scripts parse"

# --- 7. pending.tsv sanity (warn only) -------------------------------------
info "Checking pending.tsv rows"
while IFS=$'\t' read -r cmd reason cmdline; do
    [ -n "${cmd:-}" ] || continue
    [ -n "${cmdline:-}" ] || warn "pending.tsv: '$cmd' has an empty command_line"
done < <(tsv_rows "$J/manifests/pending.tsv")
ok "pending.tsv checked"

# --- 8. Native just parse --------------------------------------------------
info "Native just parse of generated Justfile"
if command -v just >/dev/null 2>&1; then
    if just_err=$(just --justfile "$T/Justfile" --summary 2>&1 >/dev/null); then
        ok "just parses the generated Justfile"
    else
        fail "just failed to parse Justfile: $just_err"
    fi
else
    fail "just not installed — required to validate the generated Justfile (need >= 1.52)"
fi

# --- 9. scan.json (warn: absent in NO-GIT targets) -------------------------
info "Checking incremental-scan state"
S="$J/state/scan.json"
if [ -f "$S" ] && [ -s "$S" ]; then
    if grep -q '"version"' "$S" && grep -q '"baseline_ref"' "$S"; then
        ok "scan.json present with required keys"
    else
        fail "scan.json malformed: missing \"version\" or \"baseline_ref\""
    fi
else
    warn "scan.json absent (expected for non-git targets; otherwise run scan-baseline.sh first)"
fi

# --- Result ----------------------------------------------------------------
echo
if [ "$errors" -eq 0 ]; then
    ok "validate-generated passed (0 errors)."
    exit 0
fi
die "validate-generated failed with $errors error(s)."
