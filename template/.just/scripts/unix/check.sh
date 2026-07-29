#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

rc=0
info "Config check"
bash "$SCRIPTS_DIR/unix/config.sh" check || rc=1
info "Health check"
bash "$SCRIPTS_DIR/unix/health.sh" || rc=1

if [ "$rc" -eq 0 ]; then ok "check passed"; else err "check failed"; fi
exit "$rc"
