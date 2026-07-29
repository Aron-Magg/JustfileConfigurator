#!/usr/bin/env bash
# Smoke test: instantiate the template into a scratch dir and exercise the
# read-only / safe recipes. Run from anywhere: bash tests/smoke_unix.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pass=0; fail=0
run() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf 'ok   %s\n' "$desc"; pass=$((pass + 1))
    else
        printf 'FAIL %s\n' "$desc"; fail=$((fail + 1))
    fi
}

command -v just >/dev/null 2>&1 || { echo "just not installed — cannot run smoke test"; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$ROOT/template/." "$stage/"
cd "$stage"

echo "== Unix smoke test (staged in $stage) =="
run "just --list parses"          just --list
run "just platform"               just platform
run "just platforms"              just platforms
run "just health-all"             just health-all
run "just config init"            just config init
run "just config check"           just config check
run "just config diff"            just config diff
run "just cure-plan"              just cure-plan
run "just pending"                just pending
run "just db backup (disabled)"   just db backup
run "just tests all"              just tests all
run "just reports all"            just reports all
run "just status"                 just status

echo "-----"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
