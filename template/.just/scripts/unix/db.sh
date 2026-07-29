#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# DB_ENABLED is exported by just (dotenv-load). Default to disabled.
DB_ENABLED="${DB_ENABLED:-false}"
BACKUP_DIR="$TEMPLATE_ROOT/backups/db"
mkdir -p "$BACKUP_DIR"

if [ "$DB_ENABLED" != "true" ]; then
    warn "DB_ENABLED is not 'true' — database module disabled. Set DB_ENABLED=true in .env to use it."
    exit 0
fi

action="${1:-}"
case "$action" in
    backup)
        ts="$(date +%Y%m%d-%H%M%S)"
        out="$BACKUP_DIR/backup-$ts.sql"
        info "Backing up database -> $out"
        # TODO: real dump, e.g. pg_dump "$DATABASE_URL" > "$out"
        printf -- '-- placeholder backup created at %s\n' "$ts" > "$out"
        ok "Backup written: $out"
        ;;
    restore)
        file="${2:-}"
        [ -n "$file" ] || die "restore requires a FILE argument"
        [ -f "$file" ] || die "File not found: $file"
        info "Restoring database from $file"
        # TODO: real restore, e.g. psql "$DATABASE_URL" < "$file"
        ok "Restore complete (placeholder)."
        ;;
    reset)
        info "Resetting database"
        # TODO: real reset (drop + migrate)
        ok "Reset complete (placeholder)."
        ;;
    *)
        die "Unknown db action: $action (use backup|restore FILE|reset)"
        ;;
esac
