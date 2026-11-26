# Shared agent instructions

OrcaVault is the UMCCR data warehouse: a dbt project (SQL) on Amazon Redshift, modelled with
Data Vault 2.0 and dimensional marts. Architecture: [docs/architecture/README.md](docs/architecture/README.md).
Docs index: [docs/README.md](docs/README.md).

This file is the single source of agent rules for all agents. Kiro loads it natively,
`CLAUDE.md` imports it, and `.kiro/steering/` holds pointers only. Use plain links here,
not `@` imports.

## Before implementation

- Read the OpenSpec change under `openspec/changes/<name>/` for the work in progress, if
  there is one, and the current behaviour in `openspec/specs/`.
- Check `docs/` for architecture and decisions (`docs/decisions/`).
- Search the repository (models, macros) before creating new models or macros.
- Inspect related tests (`tests/`, model `_schema.yml`) before changing behaviour.

## Standards

- Respect files and directories whose names start with a dot (`.`); do not treat them as
  disposable or auto-generated unless proven so.
- Ask permission before reading `.env`, and never echo secret values.
- Ignore anything under `.local/` unless the user points you to a file there; it is local
  scratch, not part of the project.
- Warehouse data is clinical genomics metadata. Never copy query results, identifiers
  (subject, sample, library IDs) or other real records into code, fixtures, specs, docs,
  commit messages or PRs. Use synthetic examples.
- Do not bypass the pre-commit hooks or edit `.secrets.baseline` by hand
  (`make baseline` regenerates it).
- Work on a branch; the `no-commit-to-branch` hook blocks commits to `main`.

## dbt rules

Setup and commands: [README.md](README.md), [docs/dev/README.md](docs/dev/README.md),
[docs/dev/personal-schemas.md](docs/dev/personal-schemas.md).

- Follow the layer folders and model prefixes (`hub_`, `link_`, `sat_`, `effsat_`, ...).
- Do not hard-code schema names; `macros/generate_schema_name.sql` resolves them.
- Reuse the shared macros (`generate_hash_diff`, `generate_s3object_hk`, `extract_*`,
  `cdc_fill_delete`) rather than re-implementing keys or parsing.
- Incremental CDC models use the watermark macros:
  [cdc-models.md](docs/dev/cdc-models.md). Do not edit `ops.cdc_watermark` unless told to.
- Deletes pass through the raw vault and close in an effectivity satellite:
  [cdc-deletes.md](docs/architecture/cdc-deletes.md).
- dbt is in `.venv/` (`pre-commit` comes from the `Brewfile`). Each shell call starts fresh, so prefix commands
  with `source .venv/bin/activate &&` (and `source dx.sh &&` for the `house_*`/`dbt_*` functions).
- Build and validate in your personal schema, not the shared dev schema, unless told
  otherwise.
- In shared or production schemas, never run a project-wide `--full-refresh`, and never fully
  refresh the raw vault (hubs above all) or the PSA without a core maintainer's agreement. The
  business vault may be refreshed by name. See [data-vault.md](docs/architecture/data-vault.md).
  Read [ica-usage.md](docs/dev/ica-usage.md) before rebuilding the ICA usage models.
- Test fixtures under `tests/fixtures/` are synthetic only.

## Docs and specs

- Do not grow `README.md`. It is the landing page (about one screen: links, Quickstart,
  Redshift, Documentation), capped at 60 lines by a pre-commit hook. Put a new how-to or note
  in its own file, `docs/dev/<topic>.md`, and add one line for it to the Index in
  [docs/README.md](docs/README.md).
- Read [docs/README.md](docs/README.md) (where things go) before adding docs, and
  [docs/decisions/README.md](docs/decisions/README.md) before adding a decision record.
  Never edit an accepted decision; supersede it.
- Changes are specified with OpenSpec in `openspec/changes/<name>/`; do not hand-edit
  `openspec/specs/` outside a change.
- When archiving a change, promote structural outcomes to `docs/` and decisions to
  `docs/decisions/`.

## During implementation

- Keep changes narrowly scoped and do not change unrelated files.
- Do not weaken tests merely to make them pass.
- If a change would only work after a `--full-refresh` of the shared or production schemas,
  treat that as a design warning, not a deployment step. Outside the business vault, first look
  for a design that applies going forward or repairs by re-reading (CDC watermark,
  `reread_from`). If none works, stop and consult a maintainer before going further.

## Before completion

- Validate in your personal schema, for example:

  ```bash
  dbt build -s <model>+ -f
  make check                # pre-commit hooks
  ```

- Check the final diff for accidental changes.
- Summarise assumptions, tests and known limitations.
