# Proposal

## Why

The CDC watermark is already built, but its behaviour has no spec. It shipped in
PR [#48](https://github.com/umccr/orcavault/pull/48) (2026-10-09), and PR
[#53](https://github.com/umccr/orcavault/pull/53) (2026-11-19) made each source table's position
move on its own (in #48 they all moved together). This baseline records the current behaviour as the `cdc-watermark` spec, so
that the next iterations can be written as changes against it.

This change is retrospective: **no code changes**. The problem it solved is
[orcahouse-project#36](https://github.com/umccr/orcahouse-project/issues/36). Comparing
`_dms_cdc_timestamp` with a model's `max(load_datetime)` missed rows that were committed before
a run but were not yet visible to it. The watermark table was proposed in
[orcahouse-project#37](https://github.com/umccr/orcahouse-project/issues/37), and per-source
tracking in [orcahouse-project#56](https://github.com/umccr/orcahouse-project/issues/56).

## What Changes

- Adds the `cdc-watermark` spec, describing the behaviour as it is in `main` today.
- Adds decision record [0003](../../../../docs/decisions/0003-cdc-watermark-per-source-table.md)
  with the design rationale and the rejected alternatives.
- Links the architecture doc to the spec and the decision record. The doc stays the "how it is
  built" reference.
- No change to models, macros, tests or the `ops.cdc_watermark` table.

## Capabilities

### New Capabilities

- `cdc-watermark`: how incremental models choose which CDC source rows to read. Covers the
  `ops.cdc_watermark` state, the read window, how a run moves each table's position forward,
  and the guard rails (personal targets, failures, partial selections).

### Modified Capabilities

None.

## Impact

- Code: none. The behaviour lives in `macros/ops/` and `macros/watermark/` and in the
  `on-run-start` / `on-run-end` hooks in `dbt_project.yml`.
- Docs: `docs/architecture/cdc-watermark.md` (adds links), `docs/decisions/` (adds 0003).
- Later iterations that change watermark behaviour must modify this spec. Candidates are listed
  in `design.md` under Open Questions.
