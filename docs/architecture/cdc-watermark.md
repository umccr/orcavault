# Incremental loading with watermarks

This document explains how incremental models decide which rows to read. A
watermark, which is a stored point in time that tells the warehouse how far along
a source is, is what allows this to occur. How to use it is in the how-to guides
listed at the end.

The main components are:

- [`macros/ops/tables.sql`](../../macros/ops/tables.sql) creates the watermark
  table, `ops.cdc_watermark`.
- [`macros/ops/queries.sql`](../../macros/ops/queries.sql) moves the watermarks at
  the start and end of each run.
- [`macros/watermark/bounds.sql`](../../macros/watermark/bounds.sql) filters rows
  that models use to incrementally load.
- [`macros/watermark/int_cdc_state.sql`](../../macros/watermark/int_cdc_state.sql)
  creates some of the current-state `int_cdc` models.

The required behaviour is specified in
[openspec/specs/cdc-watermark](../../openspec/specs/cdc-watermark/spec.md), and why it is
designed this way is in decision record
[0003](../decisions/0003-cdc-watermark-per-source-table.md).

## The design

- A model that reads a CDC source table filters on commit time, i.e. the
  `_dms_cdc_timestamp`. A model that reads another warehouse model filters on
  load time, i.e. the `load_datetime`. A filter doesn't compare one type of time
  with the other.
- `ops.cdc_watermark` has one watermark for each CDC source table, called its
  `position`. Every model has processed the table's commits up to that time.
  Models have no positions of their own.
- At the start of a run, dbt records `pending` for every table that the run
  reads. This is the point the run reads up to. The commit times after
  `position` and up to `pending`, are the table's window. This window has the
  changes that earlier runs haven't processed.
- At the end of a `dbt run` or `dbt build`, dbt moves a table's `position` up to
  a margin before its `pending`, once every model that reads the table has
  succeeded in that run. Otherwise, the position stays where it was, and the
  next run reads the window again. Each table has its watermark updated on its own, so a
  failure or a `--select` only holds back the tables that the missing models
  read.
- Every incremental model already skips rows it has, either by merging on a key
  or by checking for the row's hash, so re-reading is harmless. The watermark is
  designed to avoid losing rows rather than over-reading.

## Two kinds of time

The warehouse rows and CDC rows have different types of time that aren't
comparable.

The load time is under dbt's control. dbt handles model run dependencies, so a
model's own `max(load_datetime)` gives it which parent rows have already been
read. Models that read other warehouse models use this value, and need no stored
state.

The commit time is not under dbt's control. A CDC row is only visible once
Spectrum can return it. That needs DMS to write its file to S3, which can result
in a visibility delay. This process is outside of the warehouse dbt operation.

This means that:

- A model can't compare a CDC table with its own `max(load_datetime)`. A row
  committed before the last run, but visible after it, would be missed.
- The warehouse needs its own record of how far it has read each CDC table. That
  record is in `ops.cdc_watermark`.

## The watermark table

`create_ops_tables` creates `ops.cdc_watermark` at the start of every dbt
command:

| column                  | meaning                                                                                             |
| ----------------------- | --------------------------------------------------------------------------------------------------- |
| `source_id`             | The dbt source, i.e. `<source_name>.<table_name>`.                                                  |
| `position`              | The position every model has processed commits up to. Null means the next run reads from the start. |
| `pending`               | The newest visible commit time when the last run to read the table started. It reads up to here.    |
| `pending_invocation_id` | The dbt invocation that set `pending`. Only that invocation can move `position` up to it.           |
| `updated_at`            | The update time of the last write.                                                                  |

There is one row for each source table tagged with `cdc` in
`models/cdc/_sources.yml`. When a run finds a new table with the tag, it adds a
row with a null `position`.

### Why a table, one row per source table

The watermark state lives in a table, with one row per CDC source table, not per model and
not one global row. The reasons and the rejected alternatives are in decision record
[0003](../decisions/0003-cdc-watermark-per-source-table.md).

### Why both position and pending

`position` is the lower bound of the window and `pending` is the upper bound.
Storing `pending`, instead of reading up to the newest row is necessary
primarily because:

- The end of the run updates `position` based on where the models read up to. If
  `position` was updated with the time at the end of the run, or with the newest
  commit time at the end, rows would be missed that arrived during the run that
  weren't yet visible.

It also has the added benefit of allowing every model in the run to read the
same rows. Since DMS keeps writing while dbt runs, a late model could read a row
that its parent didn't see, as it ran earlier. This would result in test
failures.

The `pending_invocation_id` stops any other runs from accidentally updating the
`pending`, and ensures that only that `pending_invocation_id` can update that
row.

At the end of the run, `position` is set to a margin before `pending`, so the
next run reads the last few minutes again. This catches rows committed before
`pending` that weren't visible yet, such as a transaction split across two DMS
files.

### Which positions get updated

Each table's `position` is updated on its own, from the models that read it. A
model reads a table when it selects from the source directly, or through an
ephemeral `int_cdc` model.

- A run only sets `pending` for the tables that its selected models used, so it
  won't move the position of any other table.
- A table's `position` is updated when every model that needs it succeeded in the
  run. If one failed, was skipped or wasn't selected, the position stays.
- Models downstream that don't depend on the `position` aren't part of this, as they
  use `load_bound`.

A failure in a full run only prevents updating watermarks for tables that the failed and
skipped models read. A run with `--select` updates a watermark only when it covers all
of the table's readers, such as
`dbt build --select source:orcabus_sequence_run_manager+`.

## The bound macros

The models never read `ops.cdc_watermark` directly. They use these macros from
`macros/watermark/bounds.sql` instead:

| macro                            | condition                                                                            | use it when                                                                   |
| -------------------------------- | ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| `cdc_upper_bound(source, table)` | commit time `<= pending`                                                             | A model needs every row up to `pending`, such as a lookup or a current state. |
| `cdc_window(source, table)`      | `position <` commit time `<= pending`                                                | A model needs only the rows that changed in this run.                         |
| `cdc_bound(source, table)`       | `cdc_window` when incremental, otherwise `cdc_upper_bound`                           | A model reads one CDC table directly.                                         |
| `load_bound()`                   | `load_datetime >` this model's `max(load_datetime)` when incremental, otherwise true | A model reads another warehouse model.                                        |

Each `cdc_` macro takes an optional argument, the commit time expression, which
is needed for table aliases, such as `'stt._dms_cdc_timestamp'`.

A null `position` in the table means no lower bound, and a null `pending` means
no upper bound. For a build that isn't incremental, such as the first build, the
logic still stops at `pending`.

The reason these macros exist is because they standardise the behaviour across
the models and also allow testing to happen. Without them, unit tests wouldn't
be able to test `ops.cdc_watermark`. How the macros are composed within a model
is left up to the model.

## How-to

- [dev/cdc-models.md](../dev/cdc-models.md): using the bounds when writing a CDC source or model.
- [dev/cdc-watermark-ops.md](../dev/cdc-watermark-ops.md): fixing or re-reading watermarks
  (maintainers only).
