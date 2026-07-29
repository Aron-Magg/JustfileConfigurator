# desktop.just — OPTIONAL module (loaded via `mod? desktop`).
# Safe to delete this file: the root Justfile's `mod?` makes it non-fatal.

set working-directory := '../..'

# Show the desktop subcommands.
default:
    @echo "desktop subcommands: build, run  (optional module — customise for your app)"

# Build the desktop app (placeholder).
build:
    @echo "[desktop] build — implement for your desktop toolchain."

# Run the desktop app (placeholder).
run:
    @echo "[desktop] run — implement for your desktop toolchain."
