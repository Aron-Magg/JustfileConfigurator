#!/usr/bin/env bash
# Smoke test the public Claude/Codex skill installer without touching real
# user skill directories.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT/scripts/install-skill.sh"
SKILL_NAME="justfile-template"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT

pass=0
fail=0

check() {
    local desc="$1"
    shift
    if "$@"; then
        printf 'ok   %s\n' "$desc"
        pass=$((pass + 1))
    else
        printf 'FAIL %s\n' "$desc"
        fail=$((fail + 1))
    fi
}

claude_root="$stage/claude-skills"
codex_home="$stage/codex-home"
codex_root="$codex_home/skills"
custom_codex_root="$stage/custom-codex-skills"
ignored_codex_home="$stage/ignored-codex-home"

CLAUDE_SKILLS_DIR="$claude_root" bash "$INSTALLER" install >/dev/null
claude_skill="$claude_root/$SKILL_NAME/SKILL.md"
check "Claude is the default target" test -f "$claude_skill"

CODEX_HOME="$codex_home" bash "$INSTALLER" install codex >/dev/null
codex_skill="$codex_root/$SKILL_NAME/SKILL.md"
check "Codex uses CODEX_HOME/skills" test -f "$codex_skill"
check "Claude remains installed after Codex install" test -f "$claude_skill"

check "template path is rendered" grep -Fq "$ROOT/template" "$codex_skill"
check "dist path is rendered" grep -Fq "$ROOT/dist" "$codex_skill"
check "template placeholder is absent" test "$(grep -Fc '__TEMPLATE_DIR__' "$codex_skill")" -eq 0
check "dist placeholder is absent" test "$(grep -Fc '__DIST_DIR__' "$codex_skill")" -eq 0

printf '\nSTALE_MARKER\n' >> "$codex_skill"
CODEX_HOME="$codex_home" bash "$INSTALLER" install codex >/dev/null
check "Codex reinstall refreshes the skill" test "$(grep -Fc 'STALE_MARKER' "$codex_skill")" -eq 0

CODEX_HOME="$ignored_codex_home" CODEX_SKILLS_DIR="$custom_codex_root" \
    bash "$INSTALLER" install codex >/dev/null
custom_codex_skill="$custom_codex_root/$SKILL_NAME/SKILL.md"
check "CODEX_SKILLS_DIR overrides CODEX_HOME" test -f "$custom_codex_skill"
check "overridden CODEX_HOME is untouched" test ! -e "$ignored_codex_home"

CODEX_HOME="$codex_home" bash "$INSTALLER" uninstall codex >/dev/null
check "Codex uninstall removes only its skill" test ! -e "$codex_root/$SKILL_NAME"
check "Claude survives Codex uninstall" test -f "$claude_skill"
check "custom Codex root survives other-root uninstall" test -f "$custom_codex_skill"

CODEX_HOME="$ignored_codex_home" CODEX_SKILLS_DIR="$custom_codex_root" \
    bash "$INSTALLER" uninstall codex >/dev/null
CLAUDE_SKILLS_DIR="$claude_root" bash "$INSTALLER" uninstall >/dev/null
check "custom Codex skill uninstalls cleanly" test ! -e "$custom_codex_root/$SKILL_NAME"
check "Claude skill uninstalls cleanly" test ! -e "$claude_root/$SKILL_NAME"

if CODEX_HOME="$codex_home" bash "$INSTALLER" uninstall codex >/dev/null 2>&1 \
    && CLAUDE_SKILLS_DIR="$claude_root" bash "$INSTALLER" uninstall >/dev/null 2>&1; then
    printf 'ok   repeated uninstall is idempotent\n'
    pass=$((pass + 1))
else
    printf 'FAIL repeated uninstall is idempotent\n'
    fail=$((fail + 1))
fi

if CODEX_HOME="$stage/invalid-home" bash "$INSTALLER" install unsupported >/dev/null 2>&1; then
    printf 'FAIL unsupported target is rejected\n'
    fail=$((fail + 1))
else
    printf 'ok   unsupported target is rejected\n'
    pass=$((pass + 1))
fi
check "invalid target creates no directory" test ! -e "$stage/invalid-home"

if CLAUDE_SKILLS_DIR="$stage/invalid-action" bash "$INSTALLER" unsupported claude >/dev/null 2>&1; then
    printf 'FAIL unsupported action is rejected\n'
    fail=$((fail + 1))
else
    printf 'ok   unsupported action is rejected\n'
    pass=$((pass + 1))
fi
check "invalid action creates no directory" test ! -e "$stage/invalid-action"

printf '%s passed, %s failed\n' "$pass" "$fail"
test "$fail" -eq 0
