# Tasks

Retrospective baseline: the implementation already shipped in PR #51, so the tasks below cover
only capturing and checking the spec.

## 1. Verify spec against code

- [x] 1.1 Check each requirement in `specs/cdc-deletes/spec.md` against `macros/cdc_fill_delete.sql`, the SRM `int_cdc` models, `hub_library`, `sat_library_sequencing_run_srm`, `effsat_library_sequencing_run` and the two marts; verified by reading them on `main` at 066de26
- [x] 1.2 Check the scenarios against the unit tests in `tests/fixtures/deletes/deletes.yml`; verified by reading the tests

## 2. Docs and decision

- [x] 2.1 Add decision record `docs/decisions/0004-cdc-deletes-close-in-business-vault.md` and its index row; verified by the link resolving from `docs/decisions/README.md`
- [x] 2.2 Rename `docs/architecture/srm-deletes.md` to `cdc-deletes.md`, restructure it, and link it to the spec and decision 0004; verified by no references to the old name remaining

## 3. Validate

- [x] 3.1 Run `openspec validate baseline-cdc-deletes --strict` and verify it passes
- [x] 3.2 Run the pre-commit hooks on the changed files and verify they pass

No personal-schema build is needed: no model or macro changed.

## Workflow follow-up

- Archive with `openspec archive baseline-cdc-deletes` to create `openspec/specs/cdc-deletes/spec.md`.
