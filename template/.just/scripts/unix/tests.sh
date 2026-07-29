#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

action="${1:-all}"
case "$action" in
    all)
        info "Running all tests…"
        # TODO: plug in your test runner here (pytest, cargo test, npm test, …).
        ok "Tests passed (placeholder)."
        ;;
    *)
        die "Unknown tests action: $action (use all)"
        ;;
esac
