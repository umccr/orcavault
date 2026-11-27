# 3. CDC watermark table, one row per source table

- Status: Accepted
- Date: 2026-11-19 (recorded 2026-11-26, after the fact, from the issues, PRs and warehouse
  meeting notes from 2026-09-16 to 2026-11-11)

## Context

CDC sources reach Redshift in several steps: AWS DMS writes Parquet files to S3, the Glue
Crawler catalogues them, and Spectrum reads them. A row is visible some time after it is
committed upstream. Incremental models used to compare `_dms_cdc_timestamp` (commit time) with
their own `max(load_datetime)` (dbt run time). A row committed before a run, but visible only
after it, was skipped for good. This "blackout window" bug was found on 2026-09-16
([orcahouse-project#36](https://github.com/umccr/orcahouse-project/issues/36)).

Options considered, in roughly this order. The first four come from the planning before #37,
and the rest from the #37 discussion and the PRs:

- **Filter by date** (`_dms_cdc_timestamp >= current_date - 1`). Rejected: replication lag
  loses rows.
- **Dates passed in by the orchestrator, with partition pruning** on `partition_0/1/2`.
  Rejected:
  - The run is not self-contained.
  - DMS names folders by its own clock, so it needs a two-partition window at midnight.
  - Catching up needs one run per missed day.
- **Derive the watermark from the target** (`max(load_date)` or partition date). Rejected:
  - It stalls on days with no changes.
  - A subquery bound defeats Spectrum partition pruning.
  - It mixes the load-time and commit-time timelines.
- **A physical staging copy in Redshift.** Rejected: the S3 data lake is the immutable buffer,
  so staging stays virtual (ephemeral or view).
- **Track by `$path` (file).** Rejected in favour of `_dms_cdc_timestamp`.
- **A watermark table** ([orcahouse-project#37](https://github.com/umccr/orcahouse-project/issues/37)).
  Accepted. Within it:
  - one row for the whole warehouse: not built, because quiet sources would hold busy ones
    back;
  - one row per model (suggested in the #37 discussion): not built;
  - one row per source table (decided 2026-10-02, built in PR
    [#48](https://github.com/umccr/orcavault/pull/48), 2026-10-09). In that first version all
    rows moved together: running one model waited on, and moved, every CDC table;
  - one row per source table, each moving on its own (PR
    [#53](https://github.com/umccr/orcavault/pull/53), 2026-11-19, for
    [orcahouse-project#56](https://github.com/umccr/orcahouse-project/issues/56)).
- **A run-log table in the warehouse** for run metrics (rows, duration, status), raised in #37.
  Replaced on 2026-10-20: the daily run keeps dbt's `run_results.json` (full and slimmed) as a
  partitioned data lake, queried with Athena. That lives in the orcahouse infrastructure, not in
  OrcaVault.

## Decision

We keep CDC read state in `ops.cdc_watermark`, with **one row per CDC source table**:

- `position` is the commit time every reader has processed up to.
- `pending` is the newest visible commit when the run started, and is fixed for the whole run.
- Each table's `position` moves on its own, to `pending` minus a margin, only when every model
  that reads the table succeeded in that run.
- Models read only through the bound macros, and hold no watermark state of their own.
- Models that read other warehouse models, and non-CDC batch sources, bound by
  `load_datetime`, never by commit time.
- Ordering of DMS events with the same timestamp is not resolved. The warehouse keeps business
  key and state; the fine-grained history stays in the DMS data lake.

We chose per source table, not one global row and not per model:

- When a row becomes visible depends on the source, not on the model reading it.
- A global row lets quiet sources hold busy ones back.
- Per-model rows would duplicate state that is the same for every reader.

We then made each row move on its own (PR #53). When all rows moved together, a `--select` run
had to wait on every CDC table, and it moved tables that it had not read.

The behaviour is specified in
[openspec/specs/cdc-watermark](../../openspec/specs/cdc-watermark/spec.md). How it is built
is described in [cdc-watermark.md](../architecture/cdc-watermark.md).

## Consequences

- No rows are lost to late visibility. The cost is re-reading: the margin and failed runs mean
  windows overlap, so every incremental CDC model must deduplicate.
- Partial `--select` runs are safe. A table's position waits until all its readers have
  succeeded in one run.
- Personal schemas read the shared watermarks and never write them.
- Run metrics live outside the warehouse, in the dbt run-results data lake.
- Deferred, not built:
  - partition pruning on window reads (only `s3_object` prunes, and only to find `pending`),
    carried over to the production V2 milestone;
  - a guard against overlapping runs.

## References

Warehouse meeting notes in the knowledge base (private repository):

- [2026-09-16](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-09-16-warehouse.md): blackout window bug found, watermark table proposed
- [2026-10-02](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-10-02-warehouse.md): watermark design: one row per CDC source, position and pending
- [2026-10-14](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-10-14-warehouse.md): watermark closed; positions moving independently wanted
- [2026-10-20](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-10-20-warehouse.md): run-log table replaced by the run-results data lake
- [Warehouse Production Release](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Projects/warehouse-production-release.md): project log and key decisions
