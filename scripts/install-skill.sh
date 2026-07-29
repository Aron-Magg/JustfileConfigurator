#!/usr/bin/env bash
# Install/uninstall the justfile-template skill for coding agents.
#
#   install-skill.sh install            # all detected agents (default)
#   install-skill.sh install all        # same
#   install-skill.sh install claude     # Claude only (forced)
#   install-skill.sh install codex      # Codex only (forced)
#   install-skill.sh uninstall [all|claude|codex]
set -euo pipefail
. "$(dirname "$0")/lib.sh"

SKILL_NAME="justfile-template"
SRC="$REPO_ROOT/skill/SKILL.md"

action="${1:-install}"
target="${2:-all}"

case "$action" in
    install|uninstall) ;;
    *) die "Unknown action: $action (use install|uninstall [all|claude|codex])" ;;
esac

# Registry of known agents. resolve_agent <name> sets:
#   SKILLS_ROOT  where the agent looks for skills
#   AGENT_LABEL  human-readable name
#   INVOKE_HINT  how to call the skill
#   FOUND        yes/no — is this agent present on this machine?
AGENTS="claude codex"

resolve_agent() {
    case "$1" in
        claude)
            SKILLS_ROOT="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
            AGENT_LABEL="Claude"
            INVOKE_HINT="Ask Claude to use the justfile-template skill."
            if [ -n "${CLAUDE_SKILLS_DIR:-}" ] || [ -d "$HOME/.claude" ]; then FOUND=yes; else FOUND=no; fi
            ;;
        codex)
            SKILLS_ROOT="${CODEX_SKILLS_DIR:-${CODEX_HOME:-$HOME/.codex}/skills}"
            AGENT_LABEL="Codex"
            INVOKE_HINT='Invoke it in Codex with: $justfile-template'
            if [ -n "${CODEX_SKILLS_DIR:-}" ] || [ -n "${CODEX_HOME:-}" ] || [ -d "$HOME/.codex" ]; then FOUND=yes; else FOUND=no; fi
            ;;
        *) return 1 ;;
    esac
}

install_one() {
    resolve_agent "$1" || die "Unknown agent: $1"
    [ -f "$SRC" ] || die "skill source not found: $SRC"
    local dir="$SKILLS_ROOT/$SKILL_NAME"
    mkdir -p "$dir"
    # Substitute the real absolute paths so the skill points at this repo.
    sed -e "s#__TEMPLATE_DIR__#$TEMPLATE_DIR#g" \
        -e "s#__DIST_DIR__#$DIST_DIR#g" \
        "$SRC" > "$dir/SKILL.md"
    ok "Installed $AGENT_LABEL skill '$SKILL_NAME' -> $dir/SKILL.md"
    info "$INVOKE_HINT"
}

uninstall_one() {
    resolve_agent "$1" || die "Unknown agent: $1"
    local dir="$SKILLS_ROOT/$SKILL_NAME"
    if [ -d "$dir" ]; then
        rm -rf -- "$dir"
        ok "Removed $AGENT_LABEL skill '$SKILL_NAME' from $SKILLS_ROOT"
    else
        warn "$AGENT_LABEL skill '$SKILL_NAME' is not installed in $SKILLS_ROOT"
    fi
}

act_one() { [ "$action" = install ] && install_one "$1" || uninstall_one "$1"; }

case "$target" in
    all)
        did=0
        for a in $AGENTS; do
            resolve_agent "$a"
            if [ "$FOUND" = yes ]; then
                act_one "$a"
                did=$((did + 1))
            else
                info "Skipping $AGENT_LABEL — not detected."
            fi
        done
        if [ "$did" -eq 0 ]; then
            warn "No agents detected. Force one with: install-skill-claude / install-skill-codex"
        fi
        ;;
    claude|codex)
        act_one "$target"
        ;;
    *)
        die "Unknown target: $target (use all|claude|codex)"
        ;;
esac
