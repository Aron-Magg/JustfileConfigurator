#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

info "Setting up project…"
bash "$SCRIPTS_DIR/unix/config.sh" init || true
info "Checking tools…"
bash "$SCRIPTS_DIR/unix/health.sh" || warn "Some tools are missing — run: just cure-plan"
ok "Setup complete."
