# Design

## Context

This is a baseline. It records behaviour that is already in `main`; see proposal.md under Why.
The full description of how it is built is in
[docs/architecture/cdc-watermark.md](../../../../docs/architecture/cdc-watermark.md),
and this file does not repeat it. The rationale and the rejected alternatives are in decision
record [0003](../../../../docs/decisions/0003-cdc-watermark-per-source-table.md).

Where the behaviour lives:

- `macros/ops/tables.sql`: creates `ops.cdc_watermark` (`on-run-start`).
- `macros/ops/queries.sql`: sets `pending` at run start, and advances `position` at run end
  (`on-run-end`).
- `macros/watermark/bounds.sql`: the bound macros models use (`cdc_bound`, `cdc_window`,
  `cdc_upper_bound`, `load_bound`).
- `macros/watermark/int_cdc_state.sql`: the current-state `int_cdc` models and `cdc_changed`.
- Tests: `assert_cdc_sources_bounded`, `assert_cdc_positions_valid`, and unit tests that use
  the `cdc_watermark_overrides` var (`tests/fixtures/watermark/`).

## Goals / Non-Goals

**Goals:**

- Capture the current watermark behaviour as testable requirements.
- Give the next iterations a spec to modify, instead of rewriting the architecture doc.

**Non-Goals:**

- Changing any behaviour, fixing known gaps, or renaming macros.
- Splitting the how-to parts out of the architecture doc. That is a separate docs change.

## Decisions

These are summaries. Decision record 0003 has the full reasoning.

- **State in a table, not derived from target rows.** Rejected: `max(load_datetime)` compared
  with commit time (the #36 bug); dates passed in by the orchestrator, with partition pruning.
- **One row per source table, not per model and not one global row.** A row's visibility
  depends on the source, not on the reader. A global row would hold busy sources back behind
  quiet ones. PR #48 already had one row per source, but all rows moved together, so a
  `--select` run waited on, and moved, every CDC table. PR #53 made each row move on its own.
- **Commit time (`_dms_cdc_timestamp`), not partition date or `$path`.** Millisecond precision.
  It needs no fix at the midnight partition boundary.
- **`pending` fixed at run start, with a margin on `position`.** Every model in a run sees the
  same rows, and late-visible rows are re-read rather than lost.
- **Virtual staging only.** `int_cdc` models are ephemeral, so nothing is copied out of the
  S3 data lake into Redshift storage.

Layers affected: `cdc/` (int_cdc), `dcl/raw_vault/`, and `dcl/business_vault/` through
`load_bound`. Mart columns do not change. No full refresh is needed, and load history is kept.

## Risks / Trade-offs

- [Overlapping runs] `load_bound` assumes runs do not overlap, and nothing enforces it →
  operating guidance only; see Open Questions.
- [DMS full reload] Reloaded rows share one commit time, so models in one run can see different
  rows → do not run dbt during a DMS reload (operating guidance).
- [Manual deletes] Deleting warehouse rows does not move `position` → move the position back
  by hand.
- [Fixed margin] The 10-minute margin is a setting, not measured from DMS visibility lag → a
  row that becomes visible later than the margin is missed until the position is moved back.
- [Scan cost] Window reads do not prune partitions. Only `s3_object` prunes, and only when
  looking up `pending` → each model's read scans every partition of its CDC source.

## Open Questions

Run metrics (raised in #37) are not a candidate: since 2026-10-20 the daily run keeps dbt's
`run_results.json` as a data lake in the orcahouse infrastructure.

Candidates for follow-up changes. Each one would modify the `cdc-watermark` spec, so none is
decided here:

1. Partition pruning on window reads for every CDC source, not only `s3_object` and not only
   for `pending`.
2. A guard against overlapping shared runs (a lock or invocation check).
3. Detecting DMS full reloads, or guarding runs against them.
4. Whether the margin should come from observed DMS visibility lag.
