#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

errors=0
fail() { err "$*"; errors=$((errors + 1)); }

info "Validating JustfileConfigurator"

# --- 1. Required files exist ----------------------------------------------
info "Checking required files"
required_files=(
    "LICENSE"
    "template/Justfile"
    "template/README.md"
    "template/.env.example"
    "template/.editorconfig"
    "template/.gitattributes"
    "template/.gitignore"
    "template/.just/modules/project.just"
    "template/.just/modules/config.just"
    "template/.just/modules/db.just"
    "template/.just/modules/tests.just"
    "template/.just/modules/reports.just"
    "template/.just/modules/mobile.just"
    "template/.just/modules/desktop.just"
    "template/.just/manifests/commands.tsv"
    "template/.just/manifests/tools.tsv"
    "template/.just/manifests/platforms.tsv"
    "template/.just/manifests/pending.tsv"
    "template/.just/manifests/env.required"
    "template/.just/scripts/unix/lib.sh"
    "template/.just/scripts/unix/pending.sh"
    "template/.just/adapters/arch.sh"
    "template/.just/adapters/debian.sh"
    "template/.just/adapters/macos.sh"
    "template/.just/adapters/windows.ps1"
    "docs/index.html"
    "docs/STRUCTURE.md"
    "docs/assets/styles.css"
    "docs/assets/app.js"
    "skill/SKILL.md"
    "scripts/install-skill.sh"
    "tests/smoke_skill_install.sh"
)
for f in "${required_files[@]}"; do
    if [ -e "$REPO_ROOT/$f" ]; then ok "$f"; else fail "missing: $f"; fi
done

# --- 2. Cross-references ---------------------------------------------------
info "Checking references (Justfile -> modules)"
while read -r path; do
    [ -n "$path" ] || continue
    if [ -f "$TEMPLATE_DIR/$path" ]; then ok "import/mod -> $path"; else fail "import/mod target missing: $path"; fi
done < <(grep -oE "(import|mod\??)[[:space:]]+[^']*'[^']+'" "$TEMPLATE_DIR/Justfile" | grep -oE "'[^']+'" | tr -d "'")

info "Checking references (modules -> scripts)"
# Modules reference scripts by basename via the {{_unix}}/{{_win}} variables,
# so match the basenames and confirm each exists under scripts/unix or windows.
while read -r base; do
    [ -n "$base" ] || continue
    if [ -f "$TEMPLATE_DIR/.just/scripts/unix/$base" ] || [ -f "$TEMPLATE_DIR/.just/scripts/windows/$base" ]; then
        ok "script -> $base"
    else
        fail "referenced script missing: $base"
    fi
done < <(grep -rhoE '[A-Za-z0-9_-]+\.(sh|ps1)' "$TEMPLATE_DIR/.just/modules" | sort -u)

# --- 3. TSV column counts --------------------------------------------------
info "Checking TSV column counts"
check_tsv_cols() {
    local file="$1" want="$2" line n=0 bad=0
    while IFS= read -r line; do
        n=$((n + 1))
        [ -n "$line" ] || continue
        case "$line" in \#*) continue ;; esac
        local cols; cols=$(awk -F'\t' '{print NF}' <<< "$line")
        if [ "$cols" -ne "$want" ]; then fail "$file line $n has $cols columns (want $want)"; bad=1; fi
    done < "$file"
    [ "$bad" -eq 0 ] && ok "$(basename "$file"): $want columns"
}
check_tsv_cols "$TEMPLATE_DIR/.just/manifests/tools.tsv" 8
check_tsv_cols "$TEMPLATE_DIR/.just/manifests/commands.tsv" 5
check_tsv_cols "$TEMPLATE_DIR/.just/manifests/platforms.tsv" 5
check_tsv_cols "$TEMPLATE_DIR/.just/manifests/pending.tsv" 3

# --- 4. Platform order Arch -> Debian -> macOS -> Windows ------------------
info "Checking platform order"
tools_hdr=$(head -1 "$TEMPLATE_DIR/.just/manifests/tools.tsv")
if [ "$(cut -f2-5 <<< "$tools_hdr")" = "$(printf 'arch\tdebian\tmacos\twindows')" ]; then
    ok "tools.tsv columns ordered arch,debian,macos,windows"
else
    fail "tools.tsv columns not in order arch,debian,macos,windows: $(cut -f2-5 <<< "$tools_hdr")"
fi
plat_order=$(tsv_rows "$TEMPLATE_DIR/.just/manifests/platforms.tsv" | cut -f1 | paste -sd, -)
if [ "$plat_order" = "arch,debian,macos,windows" ]; then
    ok "platforms.tsv rows ordered arch,debian,macos,windows"
else
    fail "platforms.tsv rows not in order: $plat_order"
fi

# --- 5. Bash syntax --------------------------------------------------------
info "Checking Bash syntax (bash -n)"
sh_bad=0
while read -r sh; do
    if bash -n "$sh" 2>/dev/null; then :; else fail "bash -n failed: ${sh#"$REPO_ROOT/"}"; sh_bad=1; fi
done < <(find "$REPO_ROOT/template" "$REPO_ROOT/scripts" "$REPO_ROOT/tests" -name '*.sh' -type f 2>/dev/null | sort)
[ "$sh_bad" -eq 0 ] && ok "all Bash scripts parse"

# --- 6. Skill installer smoke test -----------------------------------------
info "Checking Claude/Codex skill installer"
if bash "$REPO_ROOT/tests/smoke_skill_install.sh"; then
    ok "skill installer smoke test"
else
    fail "skill installer smoke test failed"
fi

# --- 7. Generated JS syntax ------------------------------------------------
info "Checking generated project-data.js"
pdata="$DOCS_DIR/assets/project-data.js"
if [ -f "$pdata" ]; then
    if command -v node >/dev/null 2>&1; then
        if node --check "$pdata" 2>/dev/null; then ok "project-data.js parses (node --check)"; else fail "project-data.js has a JS syntax error"; fi
    else
        warn "node not found — skipping JS syntax check"
    fi
else
    warn "project-data.js not generated yet — run: just docs-build"
fi

# --- 8 & 9. Native checks that need a full toolchain ----------------------
info "Native toolchain checks"
if command -v just >/dev/null 2>&1; then
    if just --justfile "$TEMPLATE_DIR/Justfile" --summary >/dev/null 2>&1; then
        ok "native just parse of template/Justfile"
    else
        fail "native just parse failed for template/Justfile"
    fi
else
    warn "MISSING: native just parse (just not installed) — make mandatory in CI"
fi
if command -v pwsh >/dev/null 2>&1; then
    ok "pwsh available (smoke handled by tests/smoke_windows.ps1)"
else
    warn "MISSING: pwsh .ps1 smoke (PowerShell not installed) — make mandatory in Windows CI"
fi

# --- Result ----------------------------------------------------------------
echo
if [ "$errors" -eq 0 ]; then
    ok "validate passed ($errors errors). See MISSING lines above for checks deferred to CI."
    exit 0
fi
die "validate failed with $errors error(s)."
