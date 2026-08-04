#!/usr/bin/env bash
# lib.sh — shared helpers for the configurator's own tooling. Source, don't run.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_DIR="$REPO_ROOT/template"
DOCS_DIR="$REPO_ROOT/docs"
DIST_DIR="$REPO_ROOT/dist"
SCRIPTS_DIR="$REPO_ROOT/scripts"

# Project version — single source of truth in the repo-root VERSION file.
VERSION="$(cat "$REPO_ROOT/VERSION" 2>/dev/null || echo 0.0.0)"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GRN=$'\033[32m'
    C_YLW=$'\033[33m'; C_BLU=$'\033[34m'; C_DIM=$'\033[2m'
else
    C_RESET=; C_RED=; C_GRN=; C_YLW=; C_BLU=; C_DIM=
fi
info() { printf '%s\n' "${C_BLU}==>${C_RESET} $*"; }
ok()   { printf '%s\n' "${C_GRN}ok ${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YLW} ! ${C_RESET} $*" >&2; }
err()  { printf '%s\n' "${C_RED}xx ${C_RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

# Emit the data rows of a TSV, skipping the header and comment/blank lines.
tsv_rows() {
    local file="$1"
    [ -f "$file" ] || return 0
    tail -n +2 "$file" | grep -vE '^[[:space:]]*(#|$)' || true
}

# JSON-escape a string and wrap it in quotes.
json_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    printf '"%s"' "$s"
}
