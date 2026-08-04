# Structure specification

JustfileConfigurator has two nested deliverables:

1. **The configurator** (repo root) — validates, documents and packages the template.
2. **`template/`** — the payload copied into new projects.

## Configurator layout

```text
JustfileConfigurator/
├── Justfile              # manage the configurator
├── VERSION               # single source of truth for the version
├── docs/                 # this spec + the HTML dashboard
│   ├── index.html
│   ├── STRUCTURE.md
│   └── assets/           # styles.css, app.js, project-data.js (generated)
├── scripts/              # validate.sh, validate-generated.sh, scan-baseline.sh, docs-build.sh, package.sh, lib.sh
├── tests/                # smoke_unix.sh, smoke_windows.ps1
├── dist/                 # generated archives
└── template/             # distributable template (see below)
```

`validate-generated.sh` and `scan-baseline.sh` are **skill-runtime helpers** (invoked by the
`justfile-template` skill against a target project, not `just` recipes): the first is a
correctness gate for a generated project, the second maintains the incremental-scan baseline.

## Template layout

```text
template/
├── Justfile              # import project.just; mod config/db/tests/reports; mod? mobile/desktop
├── README.md
├── .env.example
├── .editorconfig
├── .gitattributes
├── .gitignore
├── VERSION               # template version, shown by `just version`
├── .just/
│   ├── modules/          # project, config, db, tests, reports, mobile, desktop
│   ├── manifests/        # commands.tsv, tools.tsv, platforms.tsv, env.required
│   ├── scripts/          # unix/ (bash), windows/ (ps1 placeholders)
│   ├── adapters/         # arch.sh, debian.sh, macos.sh, windows.ps1
│   └── state/            # scan.json — committed incremental-scan baseline
├── backups/db/
└── reports/
```

## Five-layer architecture

```text
Justfile
   ↓  imports + mods
Functional modules (.just/modules)      WHAT to do
   ↓  dispatch
Bash / PowerShell scripts (.just/scripts)
   ↓  call
OS adapters (.just/adapters)            HOW to do it
   ↓  read
Declarative manifests (.just/manifests) data, not code
```

- **Modules** (`config`, `db`, `tests`, `reports`, `mobile`, `desktop`) define *what*.
- **Adapters** define *how*: Arch → `pacman`, Debian → `apt-get`, macOS → `brew`, Windows → `winget`.
- OS-sensitive recipes use the `[unix]` / `[windows]` attributes (never the deprecated `windows-shell`).
- Each module sets its own `shell` and `working-directory`, so it works both as a subcommand
  (`just db backup`) and with the path syntax (`just db::backup`).
- `mobile` and `desktop` are optional (`mod?`, available since `just` 1.52) and can be deleted.

## OS-aware manifests

`tools.tsv` is not a flat global list — each tool carries its package name per OS:

```text
command · arch · debian · macos · windows · required/optional · platforms · description
```

This prevents Windows from requiring Bash, Linux from requiring PowerShell, and `cure`
from trying to install packages that do not apply to the current platform. All OS-specific
knowledge lives in the manifests and adapters, never duplicated inside modules.

## Adding a new OS

1. Add a row to `platforms.tsv` (keep the Arch → Debian → macOS → Windows order).
2. Add a package column to `tools.tsv`.
3. Create `.just/adapters/<os>.sh` implementing `pkg_mgr` / `pkg_check` / `pkg_install` / `pkg_install_cmd`.
4. Extend `detect_platform()` in `.just/scripts/unix/lib.sh`.
5. Add `[<os>]` recipe variants where behaviour differs.

## Dashboard

`docs/index.html` reads `docs/assets/project-data.js`, which `just docs-build` regenerates from
the real template tree and the manifests. No data is hand-duplicated in the HTML.
