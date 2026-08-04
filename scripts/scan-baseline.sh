#!/usr/bin/env bash
# scan-baseline.sh — incremental-scan helper for the justfile-template skill.
#
# Maintains a dedicated git ref that snapshots the target project's worktree and
# prints the set of files the skill should analyse:
#   * FIRST-RUN   — no baseline yet: analyse the whole project, create the baseline.
#   * INCREMENTAL — baseline exists: analyse only what changed since it.
#   * NO-GIT      — target isn't a git repo: full scan via find, no baseline.
#
# It is deliberately non-invasive: it NEVER switches HEAD, NEVER stages anything
# in the real index, and NEVER edits your working files. The one intentional
# worktree write is the committed state file .just/state/scan.json.
#
# Usage:
#   scan-baseline.sh <TARGET_DIR> [scan|advance|init] [--print0] [--force]
#                    [advance --add-settled <path>...]
#
# stdout contract (parseable): line 1 is `MODE=<FIRST-RUN|INCREMENTAL|NO-GIT>`,
# remaining lines are project-relative file paths (NUL-separated with --print0).
# All human-readable logging goes to stderr.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

REF="refs/heads/justfile-configurator/baseline"
STATE_REL=".just/state/scan.json"

# Stable identity so commit-tree never fails on a repo with no user.* config.
export GIT_AUTHOR_NAME="justfile-configurator"  GIT_AUTHOR_EMAIL="configurator@localhost"
export GIT_COMMITTER_NAME="justfile-configurator" GIT_COMMITTER_EMAIL="configurator@localhost"

say() { printf '%s\n' "$*" >&2; }

# --- Argument parsing ------------------------------------------------------
TARGET=""; CMD="scan"; PRINT0=0; FORCE=0; ADD_SETTLED=()
while [ $# -gt 0 ]; do
    case "$1" in
        --print0)      PRINT0=1 ;;
        --force)       FORCE=1 ;;
        --add-settled) shift; [ $# -gt 0 ] || die "--add-settled needs a path"; ADD_SETTLED+=("$1") ;;
        scan|advance|init) CMD="$1" ;;
        -*)            die "unknown flag: $1" ;;
        *)             [ -z "$TARGET" ] && TARGET="$1" || die "unexpected argument: $1" ;;
    esac
    shift
done
[ -n "$TARGET" ] || die "usage: scan-baseline.sh <TARGET_DIR> [scan|advance|init] [--print0]"
[ -d "$TARGET" ] || die "not a directory: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"

# --- Temp-file cleanup -----------------------------------------------------
TMPFILES=()
cleanup() { local f; for f in "${TMPFILES[@]:-}"; do [ -n "${f:-}" ] && rm -f "$f"; done; }
trap cleanup EXIT

# --- Path filters (operate on TARGET-relative paths) -----------------------
is_scaffold() {
    case "$1" in
        .just/*|Justfile|Justfile.bak|VERSION|reports/*|backups/*|.env|.env.*) return 0 ;;
    esac
    return 1
}
SETTLED=()
is_settled() {
    local p="$1" s
    [ "${#SETTLED[@]}" -gt 0 ] || return 1
    for s in "${SETTLED[@]}"; do
        [ -n "$s" ] || continue
        case "$s" in
            */) case "$p" in "$s"*) return 0 ;; esac ;;
            *)  [ "$p" = "$s" ] && return 0 ;;
        esac
    done
    return 1
}

# ─────────────────────────────── NO-GIT ───────────────────────────────────
if ! git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'MODE=NO-GIT\n'
    warn "target is not a git repository — full scan, no baseline tracking"
    ( cd "$TARGET" && find . \
        \( -path ./.git -o -path ./.just -o -path ./reports -o -path ./backups \
           -o -path ./node_modules -o -path ./.venv -o -path ./target \
           -o -path ./build -o -path ./dist \) -prune -o -type f -print ) \
      | while IFS= read -r f; do
            rel="${f#./}"
            is_scaffold "$rel" && continue
            if [ "$PRINT0" -eq 1 ]; then printf '%s\0' "$rel"; else printf '%s\n' "$rel"; fi
        done
    exit 0
fi

TOPLEVEL="$(git -C "$TARGET" rev-parse --show-toplevel)"
PREFIX="$(git -C "$TARGET" rev-parse --show-prefix)"   # "" at repo root, else "sub/dir/"
PATHSPEC="${PREFIX:-.}"
STATE_ABS="$TARGET/$STATE_REL"

# --- git plumbing (non-invasive snapshot) ----------------------------------
snapshot_tree() {                       # echoes the tree sha for the current worktree
    local tmpidx; tmpidx="$(mktemp)"; rm -f "$tmpidx"; TMPFILES+=("$tmpidx")
    GIT_INDEX_FILE="$tmpidx" git -C "$TOPLEVEL" add -A -- "$PATHSPEC" >/dev/null 2>&1
    GIT_INDEX_FILE="$tmpidx" git -C "$TOPLEVEL" write-tree
    rm -f "$tmpidx"
}
ref_exists() { git -C "$TOPLEVEL" rev-parse -q --verify "$REF^{commit}" >/dev/null 2>&1; }
make_commit() {                         # $1 tree, $2 message [, $3 = "no-parent"]
    local tree="$1" msg="$2" parent
    if [ "${3:-}" != "no-parent" ] && parent="$(git -C "$TOPLEVEL" rev-parse -q --verify "$REF^{commit}" 2>/dev/null)"; then
        git -C "$TOPLEVEL" commit-tree "$tree" -p "$parent" -m "$msg"
    else
        git -C "$TOPLEVEL" commit-tree "$tree" -m "$msg"
    fi
}

# --- state (scan.json) read/write ------------------------------------------
read_settled() {                        # emit existing settled entries, one per line
    [ -f "$STATE_ABS" ] || return 0
    local block inside
    block="$(tr '\n' ' ' < "$STATE_ABS" | grep -oE '"settled"[[:space:]]*:[[:space:]]*\[[^]]*\]' || true)"
    [ -n "$block" ] || return 0
    inside="${block#*[}"; inside="${inside%]*}"
    printf '%s\n' "$inside" | grep -oE '"[^"]*"' | sed -E 's/^"//; s/"$//' || true
}
read_field() {                          # read_field <key>  (string or number)
    [ -f "$STATE_ABS" ] || return 0
    grep -oE "\"$1\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|[0-9]+)" "$STATE_ABS" 2>/dev/null \
      | head -1 | sed -E 's/.*:[[:space:]]*//; s/^"//; s/"$//'
}
write_state() {                         # write_state <created> <updated> <runs> <sha>
    local created="$1" updated="$2" runs="$3" sha="$4" block i
    mkdir -p "$(dirname "$STATE_ABS")"
    if [ "${#SETTLED[@]}" -eq 0 ]; then
        block="[]"
    else
        block=$'[\n'
        for i in "${!SETTLED[@]}"; do
            local sep=","; [ "$i" -eq $((${#SETTLED[@]} - 1)) ] && sep=""
            block+="    $(json_str "${SETTLED[$i]}")$sep"$'\n'
        done
        block+="  ]"
    fi
    {
        printf '{\n'
        printf '  "version": 1,\n'
        printf '  "baseline_ref": %s,\n'  "$(json_str "$REF")"
        printf '  "baseline_sha": %s,\n'  "$(json_str "$sha")"
        printf '  "repo_toplevel": %s,\n' "$(json_str "$TOPLEVEL")"
        printf '  "target_prefix": %s,\n' "$(json_str "$PREFIX")"
        printf '  "created_utc": %s,\n'   "$(json_str "$created")"
        printf '  "updated_utc": %s,\n'   "$(json_str "$updated")"
        printf '  "runs": %s,\n'          "$runs"
        printf '  "settled": %s\n'        "$block"
        printf '}\n'
    } > "$STATE_ABS"
}

# strip PREFIX, filter scaffold + settled, print survivors (NUL in, chosen sep out)
emit_files() {
    local p rel
    while IFS= read -r -d '' p; do
        rel="$p"
        if [ -n "$PREFIX" ]; then
            case "$p" in "$PREFIX"*) rel="${p#"$PREFIX"}" ;; *) continue ;; esac
        fi
        [ -n "$rel" ] || continue
        is_scaffold "$rel" && continue
        is_settled  "$rel" && continue
        if [ "$PRINT0" -eq 1 ]; then printf '%s\0' "$rel"; else printf '%s\n' "$rel"; fi
    done
}

# --- Load prior state ------------------------------------------------------
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mapfile -t SETTLED < <(read_settled)
created="$(read_field created_utc)"; [ -n "$created" ] || created="$now"
runs="$(read_field runs)"; [[ "$runs" =~ ^[0-9]+$ ]] || runs=0

# merge --add-settled (dedup, preserve order)
if [ "${#ADD_SETTLED[@]}" -gt 0 ]; then
    for s in "${ADD_SETTLED[@]}"; do
        skip=0
        [ "${#SETTLED[@]}" -gt 0 ] && for e in "${SETTLED[@]}"; do [ "$e" = "$s" ] && skip=1 && break; done
        [ "$skip" -eq 0 ] && SETTLED+=("$s")
    done
fi

# ─────────────────────────────── advance ──────────────────────────────────
if [ "$CMD" = "advance" ]; then
    tree="$(snapshot_tree)"
    commit="$(make_commit "$tree" "justfile-configurator baseline (advance)")"
    git -C "$TOPLEVEL" update-ref "$REF" "$commit"
    printf 'MODE=ADVANCED\n'
    write_state "$created" "$now" "$((runs + 1))" "$commit"
    say "ok  baseline advanced -> ${commit:0:12} (settled: ${#SETTLED[@]})"
    exit 0
fi

# ──────────────────────────────── init ────────────────────────────────────
if [ "$CMD" = "init" ]; then
    if ref_exists && [ "$FORCE" -eq 0 ]; then
        die "baseline already exists — use 'init --force' to recreate, or run 'scan'"
    fi
    tree="$(snapshot_tree)"
    commit="$(make_commit "$tree" "justfile-configurator baseline (init)" no-parent)"
    git -C "$TOPLEVEL" update-ref "$REF" "$commit"
    printf 'MODE=FIRST-RUN\n'
    write_state "$now" "$now" "1" "$commit"
    say "ok  baseline initialised -> ${commit:0:12}"
    exit 0
fi

# ──────────────────────────────── scan ────────────────────────────────────
if ref_exists; then
    printf 'MODE=INCREMENTAL\n'
    cur_tree="$(snapshot_tree)"
    git -C "$TOPLEVEL" diff --name-only -z "$REF^{tree}" "$cur_tree" -- "$PATHSPEC" | emit_files
    # (Re)create the state file if it went missing; otherwise leave it untouched.
    if [ ! -f "$STATE_ABS" ]; then
        write_state "$now" "$now" "$([ "$runs" -gt 0 ] && echo "$runs" || echo 1)" "$(git -C "$TOPLEVEL" rev-parse "$REF")"
    fi
    say "ok  incremental scan against ${REF##*/} baseline"
else
    printf 'MODE=FIRST-RUN\n'
    tree="$(snapshot_tree)"
    commit="$(make_commit "$tree" "justfile-configurator baseline (initial)" no-parent)"
    git -C "$TOPLEVEL" update-ref "$REF" "$commit"
    { git -C "$TOPLEVEL" ls-files -z -- "$PATHSPEC"
      git -C "$TOPLEVEL" ls-files -z --others --exclude-standard -- "$PATHSPEC"; } | emit_files
    write_state "$now" "$now" "1" "$commit"
    say "ok  first run — baseline created at ${commit:0:12}, whole project analysed"
fi
