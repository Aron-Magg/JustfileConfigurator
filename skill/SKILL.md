---
name: justfile-template
description: Scaffold a clean, cross-platform Justfile setup into a project AND wire up its real commands. Use when the user wants to add a Justfile, "use my just template", set up modules/adapters/manifests, or bootstrap a task runner. The skill copies the structure, then scans the project to reconstruct the actual run/build/test/lint commands into the template's layout.
---

# justfile-template

Two jobs, in order: **(1)** drop the JustfileConfigurator scaffold into a project
**without clobbering existing files**, then **(2) scan the project** and populate the
template's scripts + manifests with the project's *real* commands, following the
five-layer architecture (Justfile → modules → scripts → adapters → manifests).

Do not leave the `# TODO` placeholders in place — replacing them with the detected
commands is the whole point.

## Paths

- Template source: `__TEMPLATE_DIR__`
- Archive fallback: newest `justfile-template-*.tar.gz` in `__DIST_DIR__`
- Repo helper scripts: `__SCRIPTS_DIR__` (contains `scan-baseline.sh`, `validate-generated.sh`)

---

## Step 1 — Copy the scaffold SAFELY (never overwrite project files)

Default destination = current directory. Copy **only** the scaffold; preserve everything
the project already owns.

```bash
SRC=__TEMPLATE_DIR__
DEST=.                                   # or the user's target path

# Back up an existing Justfile rather than replacing it silently.
[ -f "$DEST/Justfile" ] && cp "$DEST/Justfile" "$DEST/Justfile.bak"

# Structure + entry point (safe to copy):
cp "$SRC/Justfile"      "$DEST/Justfile"
cp -R "$SRC/.just"      "$DEST/"
cp "$SRC/.env.example"  "$DEST/.env.example"
mkdir -p "$DEST/backups/db" "$DEST/reports"
[ -e "$DEST/backups/db/.gitkeep" ] || : > "$DEST/backups/db/.gitkeep"
[ -e "$DEST/reports/.gitkeep" ]    || : > "$DEST/reports/.gitkeep"

# The template's own README goes INSIDE .just so it never clobbers the project README.
cp "$SRC/README.md" "$DEST/.just/README.md"

# Add these ONLY if the project doesn't already have them (VERSION seeds `just version`;
# a project that already versions itself with a root VERSION keeps its own):
for f in .editorconfig .gitattributes VERSION; do
    [ -e "$DEST/$f" ] || cp "$SRC/$f" "$DEST/$f"
done

# AUTO-MERGE .gitignore (append a marked block once); never overwrite:
if [ -f "$DEST/.gitignore" ]; then
    grep -q 'JustfileConfigurator' "$DEST/.gitignore" || {
        printf '\n# --- JustfileConfigurator (auto-added) ---\n.env\n/backups/db/*\n!/backups/db/.gitkeep\n/reports/*\n!/reports/.gitkeep\nJustfile.bak\n' >> "$DEST/.gitignore"
    }
else
    cp "$SRC/.gitignore" "$DEST/.gitignore"
fi
```

**Never** copy the template's `README.md`, `.gitignore`, `.gitattributes`, or
`.editorconfig` over existing project files. If unsure, diff before writing.

**Auto-ignore rule (required, every run):** always ensure the block above is present so the
JustfileConfigurator-owned local/generated files never get committed — and **only** those:
`.env`, `backups/db/*` (keep `.gitkeep`), `reports/*` (keep `.gitkeep`), and `Justfile.bak`.
Do **not** add the project's own build artefacts or stack files (e.g. `node_modules/`,
`build/`, `local.properties`) — those are the project's responsibility and are assumed
already ignored. Do **NOT** add `.just/state/` (or `.just/state/scan.json`) to `.gitignore`: the
incremental-scan baseline state is meant to be committed so re-runs work across machines.

## Step 2 — Scan the project and detect the stack

### Step 2.0 — Establish or advance the scan baseline (incremental)

Before scanning, run the baseline helper against the destination. It maintains a dedicated ref
(`refs/heads/justfile-configurator/baseline`) and committed state in `.just/state/scan.json`. It
**never** switches the branch, **never** stages anything in the index, and **never** edits the
working files — the only write is `.just/state/scan.json`.

```bash
bash __SCRIPTS_DIR__/scan-baseline.sh "$DEST"
```

Read the first line of its output:
- `MODE=FIRST-RUN`   → analyse the WHOLE project (use the detection table below).
- `MODE=INCREMENTAL` → analyse ONLY the files it lists (changed since the last run); leave every
  already-wired script/manifest untouched unless a listed file affects it.
- `MODE=NO-GIT`      → the target isn't a git repo; fall back to a full scan of the listed files.

The remaining lines are the project-relative paths to analyse. Restrict Step 2's detection to
that set.

Inspect the destination for build tooling. Detect ALL that apply and read real command
names (lockfiles pick the package manager; script/target names come from the config):

| Signal files | Stack | run | setup | test | check/lint | ci |
|---|---|---|---|---|---|---|
| `gradlew`, `build.gradle(.kts)`, `settings.gradle` | Gradle/Android | `./gradlew installDebug` (or `assembleDebug`) | `./gradlew dependencies` | `./gradlew test` | `./gradlew lint` / `ktlintCheck` / `detekt` | `./gradlew build` |
| `package.json` (+ lockfile) | Node | `<pm> run dev`/`start` | `<pm> install` | `<pm> test` | `<pm> run lint` | `<pm> run build` |
| `Cargo.toml` | Rust | `cargo run` | `cargo fetch` | `cargo test` | `cargo clippy` | `cargo build --release` |
| `pyproject.toml` / `requirements.txt` | Python | `<runner> run …` | `<runner> install` | `pytest` | `ruff check` / `flake8` | test + lint |
| `go.mod` | Go | `go run ./...` | `go mod download` | `go test ./...` | `go vet ./...` | `go build ./...` |
| `Makefile` | Make | wrap `make <target>` for the relevant targets | | | | |
| existing `justfile` / `Old_justfile` | prior recipes | fold real recipes in | | | | |

Package-manager pick for Node: `pnpm-lock.yaml`→pnpm, `yarn.lock`→yarn,
`bun.lockb`→bun, else `package-lock.json`→npm. Read `package.json` `scripts` and map the
ones that exist; don't invent scripts.

Also scan for: a database (`docker-compose*.yml` services, `DATABASE_URL`, migration
folders) → wire the `db` module; environment variables the app reads → add to
`env.required`.

## Step 3 — Populate the structure with the REAL commands

Write what you found into the layout (WHAT stays in modules; the actual commands go in
the Unix scripts; tools go in the manifests). Edit these files:

- `.just/scripts/unix/run.sh` → the run command
- `.just/scripts/unix/setup.sh` → install deps (keep the `config init` + `health` lines, add the real install)
- `.just/scripts/unix/tests.sh` → the test command(s)
- `.just/scripts/unix/check.sh` → add the project's lint/static check (keep config + health)
- `.just/scripts/unix/ci.sh` → build/full pipeline
- `.just/scripts/unix/reports.sh` → any coverage/report command, if present
- `.just/scripts/unix/db.sh` → only if a database was detected (respect `DB_ENABLED`)

Keep each script sourcing `lib.sh`, using its logging (`info`/`ok`/`die`), and running
from `$TEMPLATE_ROOT`. Preserve the `[unix]`/`[windows]` split — leave the Windows `.ps1`
stubs as placeholders.

Then update the manifests so `health`, `cure`, and the dashboard reflect reality:

- `.just/manifests/tools.tsv` → add the real tools (e.g. `java`, `node`, `cargo`, `go`)
  with per-OS packages, ordered `arch  debian  macos  windows`, required/optional, and
  the platforms column. Prefer wrappers when present (Android uses `./gradlew`, so add
  `java` as the tool, not a global `gradle`).
- `.just/manifests/commands.tsv` → add any new subcommands you introduced.
- `.just/manifests/env.required` → the env vars the app actually needs.

Do **not** add OS-specific logic to modules — new tools go in manifests (+ an adapter if a
new OS). Follow "Add a new OS" in `.just/README.md`.

### Unavailable commands → the background file (do NOT wire them live)

A detected command is **available** only if its tool resolves now
(`command -v <tool>`). For anything you found but that is **not** currently runnable —
missing tool, ambiguous mapping, or an old-justfile recipe you can't safely translate — do
**not** write a broken recipe. Park it in the background file instead:

- Append a row to `.just/manifests/pending.tsv` (tab-separated):
  `command<TAB>reason<TAB>command_line`
  e.g. `lint\tktlint not installed\t./gradlew ktlintCheck`
- The user sees them with `just pending`; installing the tool (`just cure-plan`) or editing
  the script later promotes it to a live recipe.
- When you DO wire a command whose tool might be absent at runtime, guard it in the script:
  `command -v <tool> >/dev/null 2>&1 || die "<tool> missing — see: just pending"`.

Never delete a discovered command: it is either wired into a script or parked in pending.tsv.

## Step 4 — Validate, initialise and verify

### Validate the generated setup (must pass before you report)

Run the generated-project validator. It checks the structure, cross-references, TSV columns,
Bash syntax, a **native `just` parse**, and that **no `# TODO` placeholder was left behind**.

```bash
bash __SCRIPTS_DIR__/validate-generated.sh "$DEST"
```

If it exits non-zero, fix every listed error (a leftover `# TODO`, a malformed TSV row, a broken
cross-reference, or a `just` parse error) and re-run until it passes. Only then continue.

### Initialise and verify

```bash
cd "$DEST"
just config init      # .env from .env.example (skips if present)
just --list           # confirm the grouped recipe list (includes `just version`)
just doctor           # platform + env + tools
```

`just` ≥ 1.52 is required (optional modules use `mod?`). If missing, tell the user to install it.
The generated project carries its own `VERSION` file, shown by `just version`.

### Advance the baseline

Once validation and `just doctor` pass, snapshot this analysis point so the next skill run only
looks at future changes. First add any paths you've fully handled (or that are irrelevant to the
stack, e.g. `docs/`, vendored dirs) to the `settled` array in `.just/state/scan.json`, then:

```bash
bash __SCRIPTS_DIR__/scan-baseline.sh "$DEST" advance
```

## Step 5 — Report

Tell the user, concisely:
- which stack(s) were detected and which commands were wired into which scripts;
- what was added to the manifests (tools / env);
- files that were **preserved/merged** (README, .gitignore, …) and any `Justfile.bak`;
- what still needs a human decision (e.g. an unmapped command, an old justfile to fold in,
  whether to keep `mobile`/`desktop`).
