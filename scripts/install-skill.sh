#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

SKILL_NAME="justfile-template"
SRC="$REPO_ROOT/skill/SKILL.md"
action="${1:-install}"
target="${2:-claude}"

case "$action" in
    install|uninstall) ;;
    *) die "Unknown action: $action (use install|uninstall [claude|codex])" ;;
esac

case "$target" in
    claude)
        SKILLS_ROOT="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
        AGENT_NAME="Claude"
        INVOKE_HINT="Invoke it in any project by asking Claude to use the justfile-template skill."
        ;;
    codex)
        SKILLS_ROOT="${CODEX_SKILLS_DIR:-${CODEX_HOME:-$HOME/.codex}/skills}"
        AGENT_NAME="Codex"
        INVOKE_HINT='Invoke it in Codex with: $justfile-template'
        ;;
    *)
        die "Unknown target: $target (use claude|codex)"
        ;;
esac

DEST_DIR="$SKILLS_ROOT/$SKILL_NAME"
DEST="$DEST_DIR/SKILL.md"

case "$action" in
    install)
        [ -f "$SRC" ] || die "skill source not found: $SRC"
        mkdir -p "$DEST_DIR"
        # Substitute the real absolute paths so the skill points at this repo.
        sed -e "s#__TEMPLATE_DIR__#$TEMPLATE_DIR#g" \
            -e "s#__DIST_DIR__#$DIST_DIR#g" \
            "$SRC" > "$DEST"
        ok "Installed $AGENT_NAME skill '$SKILL_NAME' -> $DEST"
        info "Template source: $TEMPLATE_DIR"
        info "$INVOKE_HINT"
        ;;
    uninstall)
        if [ -d "$DEST_DIR" ]; then
            rm -rf -- "$DEST_DIR"
            ok "Removed $AGENT_NAME skill '$SKILL_NAME' from $SKILLS_ROOT"
        else
            warn "$AGENT_NAME skill '$SKILL_NAME' is not installed in $SKILLS_ROOT"
        fi
        ;;
esac
