#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# Version: explicit arg wins; otherwise fall back to the repo-root VERSION file
# (loaded by lib.sh as $VERSION).
VERSION="${1:-$VERSION}"
[ -n "$VERSION" ] || die "usage: package.sh [VERSION]  (defaults to the VERSION file)"

mkdir -p "$DIST_DIR"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

# Ensure the dashboard data is fresh before packaging.
bash "$(dirname "$0")/docs-build.sh"

# --- Full project archive --------------------------------------------------
full="JustfileConfigurator-$VERSION"
info "Staging full project -> $full"
mkdir -p "$stage/$full"
# Copy everything except VCS, dist output and local env.
( cd "$REPO_ROOT" && \
  find . -type d -name .git -prune -o \
         -path './dist' -prune -o \
         -name '.env' -prune -o \
         -type f -print ) | while read -r f; do
    rel="${f#./}"
    mkdir -p "$stage/$full/$(dirname "$rel")"
    cp "$REPO_ROOT/$rel" "$stage/$full/$rel"
done

# --- Template-only archive -------------------------------------------------
tpl="justfile-template-$VERSION"
info "Staging template only -> $tpl"
mkdir -p "$stage/$tpl"
cp -R "$TEMPLATE_DIR/." "$stage/$tpl/"
rm -f "$stage/$tpl/.env"

# --- Build archives --------------------------------------------------------
make_archives() {
    local name="$1"
    ( cd "$stage" && tar -czf "$DIST_DIR/$name.tar.gz" "$name" )
    ok "dist/$name.tar.gz"
    if command -v zip >/dev/null 2>&1; then
        ( cd "$stage" && zip -qr "$DIST_DIR/$name.zip" "$name" )
        ok "dist/$name.zip"
    else
        warn "zip not installed — skipped dist/$name.zip"
    fi
}

info "Writing archives to dist/"
make_archives "$full"
make_archives "$tpl"

echo
ok "Packaged version $VERSION"
ls -1 "$DIST_DIR"/*"$VERSION"* 2>/dev/null | sed "s#$REPO_ROOT/##"
