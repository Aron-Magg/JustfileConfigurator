#!/usr/bin/env bash
# Smoke test the multi-agent skill installer in a sandboxed HOME, so it never
# touches the real ~/.claude or ~/.codex.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT/scripts/install-skill.sh"
SKILL_NAME="justfile-template"
REL="skills/$SKILL_NAME/SKILL.md"          # per-agent path under $HOME/.<agent>/

stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT

pass=0; fail=0
check() {
    local desc="$1"; shift
    if "$@"; then printf 'ok   %s\n' "$desc"; pass=$((pass + 1))
    else printf 'FAIL %s\n' "$desc"; fail=$((fail + 1)); fi
}

# Run the installer with a sandboxed HOME and the agent env vars cleared.
inst() { local h="$1"; shift; env -u CLAUDE_SKILLS_DIR -u CODEX_SKILLS_DIR -u CODEX_HOME HOME="$h" bash "$INSTALLER" "$@"; }

# --- default target = all, both agents detected ---
h1="$stage/h1"; mkdir -p "$h1/.claude" "$h1/.codex"
inst "$h1" install >/dev/null 2>&1
check "all: installs for detected Claude"       test -f "$h1/.claude/$REL"
check "all: installs for detected Codex"        test -f "$h1/.codex/$REL"

# --- all skips undetected agents ---
h2="$stage/h2"; mkdir -p "$h2/.claude"
inst "$h2" install >/dev/null 2>&1
check "all: installs detected Claude"           test -f "$h2/.claude/$REL"
check "all: skips undetected Codex"             test ! -e "$h2/.codex"

# --- all with no agents present: no-op, still exit 0 ---
h3="$stage/h3"; mkdir -p "$h3"
inst "$h3" install >/dev/null 2>&1
check "all: no agents -> nothing installed"     test ! -e "$h3/.claude"

# --- explicit claude forces install even when undetected ---
h4="$stage/h4"; mkdir -p "$h4"
inst "$h4" install claude >/dev/null 2>&1
check "claude: forced install when undetected"  test -f "$h4/.claude/$REL"
check "claude: leaves Codex alone"              test ! -e "$h4/.codex"

# --- explicit codex forces install via CODEX_HOME ---
h5="$stage/h5"; mkdir -p "$h5"
env -u CLAUDE_SKILLS_DIR -u CODEX_SKILLS_DIR CODEX_HOME="$h5/.codex" HOME="$h5" \
    bash "$INSTALLER" install codex >/dev/null 2>&1
check "codex: forced install via CODEX_HOME"    test -f "$h5/.codex/$REL"
check "codex: leaves Claude alone"              test ! -e "$h5/.claude"

# --- CODEX_SKILLS_DIR overrides CODEX_HOME ---
h6="$stage/h6"; mkdir -p "$h6"
env -u CLAUDE_SKILLS_DIR CODEX_HOME="$h6/ignored" CODEX_SKILLS_DIR="$h6/custom" HOME="$h6" \
    bash "$INSTALLER" install codex >/dev/null 2>&1
check "codex: CODEX_SKILLS_DIR overrides HOME"  test -f "$h6/custom/$SKILL_NAME/SKILL.md"
check "codex: overridden CODEX_HOME untouched"  test ! -e "$h6/ignored"

# --- rendering: real paths substituted, placeholders gone ---
skill="$h1/.claude/$REL"
check "template path rendered"                  grep -Fq "$ROOT/template" "$skill"
check "dist path rendered"                      grep -Fq "$ROOT/dist" "$skill"
check "scripts path rendered"                   grep -Fq "$ROOT/scripts" "$skill"
check "no __TEMPLATE_DIR__ placeholder"         test "$(grep -Fc '__TEMPLATE_DIR__' "$skill")" -eq 0
check "no __DIST_DIR__ placeholder"             test "$(grep -Fc '__DIST_DIR__' "$skill")" -eq 0
check "no __SCRIPTS_DIR__ placeholder"          test "$(grep -Fc '__SCRIPTS_DIR__' "$skill")" -eq 0

# --- reinstall refreshes a stale copy ---
printf '\nSTALE_MARKER\n' >> "$skill"
inst "$h1" install claude >/dev/null 2>&1
check "reinstall refreshes the skill"           test "$(grep -Fc 'STALE_MARKER' "$skill")" -eq 0

# --- uninstall all removes every detected agent ---
inst "$h1" uninstall >/dev/null 2>&1
check "uninstall all: Claude removed"           test ! -e "$h1/.claude/skills/$SKILL_NAME"
check "uninstall all: Codex removed"            test ! -e "$h1/.codex/skills/$SKILL_NAME"

# --- uninstall a specific agent ---
inst "$h4" uninstall claude >/dev/null 2>&1
check "uninstall claude removes only Claude"    test ! -e "$h4/.claude/skills/$SKILL_NAME"
if inst "$h4" uninstall claude >/dev/null 2>&1; then
    check "repeated uninstall is idempotent" true
else
    check "repeated uninstall is idempotent" false
fi

# --- invalid target / action are rejected and create nothing ---
if inst "$stage/bad1" install nonsense >/dev/null 2>&1; then check "invalid target rejected" false; else check "invalid target rejected" true; fi
check "invalid target creates nothing"          test ! -e "$stage/bad1/.claude"
if inst "$stage/bad2" frobnicate claude >/dev/null 2>&1; then check "invalid action rejected" false; else check "invalid action rejected" true; fi
check "invalid action creates nothing"          test ! -e "$stage/bad2/.claude"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
test "$fail" -eq 0
