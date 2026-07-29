# mobile.just — OPTIONAL module (loaded via `mod? mobile`).
# Safe to delete this file: the root Justfile's `mod?` makes it non-fatal.

set working-directory := '../..'

# Show the mobile subcommands.
default:
    @echo "mobile subcommands: build, run  (optional module — customise for your app)"

# Build the mobile app (placeholder).
build:
    @echo "[mobile] build — implement for your mobile toolchain."

# Run the mobile app (placeholder).
run:
    @echo "[mobile] run — implement for your mobile toolchain."
