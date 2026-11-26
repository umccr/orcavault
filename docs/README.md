# Documentation

Each fact lives in one place. Everything else links to it.

## Where things go

| Content                                  | Home                        | Rule                                                   |
|------------------------------------------|-----------------------------|--------------------------------------------------------|
| Model and column descriptions            | dbt `_schema.yml` / dbt docs | Generated (`make docs`). Never copied into markdown.  |
| Setup, tooling, how-to recipes, notes    | [dev/](dev/README.md)        | One topic per file. Add a line to the Index below.     |
| How the warehouse is built now           | [architecture/](architecture/README.md) | Living. Update when design changes.      |
| Why a decision was made                  | [decisions/](decisions/README.md)       | High bar, numbered, immutable. Supersede, never edit.  |
| Current behaviour (requirements)         | `openspec/specs/`           | Living. Updated only by archiving a change.            |
| In-flight change: proposal, design, tasks | `openspec/changes/<name>/` | Archived to `openspec/changes/archive/` when done.     |
| Agent rules                              | `AGENTS.md`                 | Brief. Link here instead of duplicating. `CLAUDE.md` and `.kiro/steering/` are pointers only. |
| `README.md`                              | repo root                   | About one screen: links and Quickstart. Capped at 60 lines. |

## Promotion rule

Archiving an OpenSpec change merges its behaviour deltas into `openspec/specs/`. In the same
change, also:

- Update the design docs in `docs/` if the structure changed.
- Record each real decision as an ADR in `docs/decisions/`.

The archived change folder is history and is no longer maintained.

## Index

- [architecture/README.md](architecture/README.md): overview: scope, layers, schemas
- [architecture/data-vault.md](architecture/data-vault.md): Data Vault production rules (which layers may be fully refreshed)
- [architecture/cdc-watermark.md](architecture/cdc-watermark.md): incremental loading with CDC watermarks
- [architecture/cdc-deletes.md](architecture/cdc-deletes.md): how deletes flow through the vault
- [dev/README.md](dev/README.md): setup: toolchain, AWS session, skills
- [dev/personal-schemas.md](dev/personal-schemas.md): building in your own schema (`dbt_defer`, `dbt_clone`)
- [dev/shared-schemas.md](dev/shared-schemas.md): exception, maintainers only: building directly into the shared dev schemas
- [dev/cdc-models.md](dev/cdc-models.md): writing incremental CDC models with the watermark bounds
- [dev/cdc-watermark-ops.md](dev/cdc-watermark-ops.md): maintainers only: re-reading and fixing CDC watermarks
- [dev/unload-schema.md](dev/unload-schema.md): deploying and running the UNLOAD schema procedure
- [dev/ica-usage.md](dev/ica-usage.md): append-only ICA usage models and rebuilding them
- [dev/spec-driven.md](dev/spec-driven.md): spec-driven changes with OpenSpec, and the coding agents (Kiro, Claude Code)
- [decisions/](decisions/README.md): decision log
