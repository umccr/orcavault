# Tasks

Retrospective baseline: the implementation already shipped in PR #48 and PR #53, so the
tasks below cover only capturing and checking the spec.

## 1. Verify spec against code

- [x] 1.1 Check each requirement in `specs/cdc-watermark/spec.md` against `macros/ops/` and `macros/watermark/` and the hooks in `dbt_project.yml`; verified by reading the macros on `main` at 066de26
- [x] 1.2 Check the test requirements against `tests/assert_cdc_sources_bounded.sql` and `tests/assert_cdc_positions_valid.sql`; verified by reading both tests

## 2. Docs and decision

- [x] 2.1 Add decision record `docs/decisions/0003-cdc-watermark-per-source-table.md` and its index row; verified by the link resolving from `docs/decisions/README.md`
- [x] 2.2 Link `docs/architecture/cdc-watermark.md` to the spec and to decision 0003; verified by the links resolving

## 3. Validate

- [x] 3.1 Run `openspec validate baseline-cdc-watermark --strict` and verify it passes
- [x] 3.2 Run `make check` and verify the pre-commit hooks pass

No personal-schema build is needed: no model or macro changed.

## Workflow follow-up

- Archive with `openspec archive baseline-cdc-watermark` to create `openspec/specs/cdc-watermark/spec.md`.
- Open follow-up changes from the Open Questions in `design.md` as needed.
