# JustfileConfigurator — manage, validate, document and package the template.
# The distributable template lives in ./template. Run `just` to see recipes.

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# List every recipe.
default:
    @just --list

# Validate structure, references, manifests and script syntax.
validate:
    @bash scripts/validate.sh

# Regenerate docs/assets/project-data.js from the real tree + manifests.
docs-build:
    @bash scripts/docs-build.sh

# Open the dashboard in the default browser.
docs-open:
    @(xdg-open docs/index.html >/dev/null 2>&1 || open docs/index.html >/dev/null 2>&1 || echo "Open docs/index.html manually") &

# Serve the docs directory over HTTP (default port 8000).
docs-serve PORT="8000":
    @echo "Serving docs on http://localhost:{{PORT}} (Ctrl-C to stop)"
    @python3 -m http.server {{PORT}} --directory docs

# Build dist archives (full project + template only) for a version.
package VERSION:
    @bash scripts/package.sh {{VERSION}}

# Install the justfile-template skill into ~/.claude/skills (override CLAUDE_SKILLS_DIR).
install-skill:
    @bash scripts/install-skill.sh install

# Remove the justfile-template skill from ~/.claude/skills.
uninstall-skill:
    @bash scripts/install-skill.sh uninstall

# Install the justfile-template skill into $CODEX_HOME/skills (override CODEX_SKILLS_DIR).
install-skill-codex:
    @bash scripts/install-skill.sh install codex

# Remove the justfile-template Codex skill from $CODEX_HOME/skills.
uninstall-skill-codex:
    @bash scripts/install-skill.sh uninstall codex

# Print the template file tree.
tree:
    @if command -v tree >/dev/null 2>&1; then tree -a -I '.git' template; else find template -not -path '*/.git/*' | sort; fi

# Remove generated dist archives.
clean:
    @rm -rf dist/* && echo "Cleaned dist/" || true
