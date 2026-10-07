# Incremental loading with watermarks

This document explains how incremental models decide which rows to read, and how
the features can be used when writing CDC sources or models. A watermark, which
is a stored point in time that tells the warehouse how far along a source is, is
what allows this to occur.

The main components are:

- [`macros/ops/tables.sql`](../macros/ops/tables.sql) creates the watermark
  table, `ops.cdc_watermark`.
- [`macros/ops/queries.sql`](../macros/ops/queries.sql) moves the watermarks at
  the start and end of each run.
- [`macros/watermark/bounds.sql`](../macros/watermark/bounds.sql) filters rows
  that models use to incrementally load.
- [`macros/watermark/int_cdc_state.sql`](../macros/watermark/int_cdc_state.sql)
  creates some the current-state `int_cdc` models.

## The design

- A model that reads a CDC source table filters on commit time, i.e. the
  `_dsm_cdc_timestamp`. A model that reads another warehouse model filters on
  load time, i.e. the `load_datetime`. A filter doesn't compare one type of time
  with the other.
- `ops.cdc_watermark` has one watermark for each CDC source table, called its
  `position`. Every model has processed the table's commits up to that time.
  Models have no positions of their own.
- At the start of a run, dbt records `pending` for every table. This is the
  point the run reads up to. The commit times after `position` and up to
  `pending`, are the table's window. This window has the changes that earlier
  runs haven't processed.
- At the end of a successful `dbt run` or `dbt build`, dbt moves each `position`
  up to its `pending`. After any other run, the positions stay where they were.
  Positions are updated all at once, and a single failure results in re-read.
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

| column                  | meaning                                                                                |
| ----------------------- | -------------------------------------------------------------------------------------- |
| `source_id`             | The dbt source, i.e. `<source_name>.<table_name>`.                                     |
| `position`              | The position the model has processed commits up to. Null means everything is read.     |
| `pending`               | The newest visible commit time when the run started. The current run reads up to here. |
| `pending_invocation_id` | The dbt invocation that set `pending`. This is used to update `position` later.        |
| `updated_at`            | The update time of the last write.                                                     |

There is one row for each source table tagged with `cdc` in
`models/cdc/_sources.yml`. When a run finds a new table with the tag, it adds a
row with a null `position`.

### Why a table

A table is used because watermarks need to be available after run, and every
model reads them during a run. Also, not every model can work out its position
from its own rows. Some models don't keep commit times, and other models depend
on multiple commit times via joins. A table allows these issues to be addressed
in a convenient and centralised place.

### Why one row per source table

A single row is used for each source table because when a row becomes visible,
it depends on the source table, not on the model that reading it. Models reading
from a source read up to the same `pending`, and after the run they have
processed rows up to this point. This means that the models don't need to carry
any position state.

A single watermark for the whole database would be a simpler approach, however
this wasn't implemented as it would mean that tables without frequent updates
would hold back busier tables, resulting in more re-reading and longer runs.

### Why both position and pending

`position` is the lower bound of the window and `pending` is the upper bound.
Storing `pending`, instead of reading up to the newest row is necessary
primarily because:

- The end of the run updates `position` to exactly where the models read up to.
  If `position` was updated with the time at the end of the run, or with the
  newest commit time, rows would be missed that arrived during the run that
  weren't yet visible.

It also has the added benefit of allowing every model in the run to read the
same rows. Since DMS keeps writing while dbt runs, a late model could read a row
that its parent didn't see, as it ran earlier. This would result in test
failures.

The `pending_invocation_id` stops any other runs from accidentally updating the
`pending`, and ensures that only that `pending_invocation_id` can update that
row.

The `pending` value also a small margin added as a safety to catch any edge
cases of ordering as DMS is writing the commit time. For example, one
transaction could in theory be split across files, or many commits can share a
timestamp. In practice this is unlikely to occur but the margin is added as it's
low cost.

## The bound macros

The models never read `ops.cdc_watermark` directly. They use these macros from
`macros/watermark/bounds.sql` instead:

| macro                            | condition                                                                            | use it when                                                                   |
| -------------------------------- | ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| `cdc_upper_bound(source, table)` | commit time `<= pending`                                                             | A model needs every row up to `pending`, such as a lookup or a current state. |
| `cdc_window(source, table)`      | `position <` commit time `<= pending`                                                | A model needs only the rows that changed in this run.                         |
| `cdc_bound(source, table)`       | `cdc_window` when incremental, otherwise `cdc_upper_bound`                           | A model reads one CDC table directly.                                         |
| `load_bound()`                   | `load_datetime >` this model's `max(load_datetime)` when incremental, otherwise true | A model reads another warehouse model.                                        |

Each `cdc_` macro takes an optional argument, which, the commit time expression,
which is needed for table aliases, such `'stt._dms_cdc_timestamp'`.

A null `position` in the table means no lower bound, and a null `pending` means
no upper bound. For a build that isn't incremental, such as the first build, the
logic still stops at `pending`.

The reason these macros exist is because they standardise the behaviour across
the models and also allow testing to happen. Without them, unit tests wouldn't
be able to test `ops.cdc_watermark`. How the macros are composed within a model
is left up to the model.

## Using the bounds in a model

In order to use the watermark table and macros, consider the following patterns.

### Reading one CDC table

Use `cdc_bound`, as in `sat_library_mm`:

```sql
from {{ source('orcabus_metadata_manager', 'app_library') }}
where {{ cdc_bound('orcabus_metadata_manager', 'app_library') }}
```

A satellite like this picks each key's latest row from the window. This window
holds every commit since the last run, meaning that a key's latest row in the
window is also its latest row overall.

### Joining multiple CDC tables

A changed row often needs a column from another table. For example, a sequencing
run state needs its sequence's `instrument_run_id`. This is from
`sat_sequencing_run_state`:

```sql
with seq_lookup as (
    select orcabus_id, instrument_run_id, max(_dms_cdc_timestamp) as _dms_cdc_timestamp
    from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_sequence') }}
    where {{ cdc_upper_bound('orcabus_sequence_run_manager', 'sequence_run_manager_sequence') }}
    group by orcabus_id, instrument_run_id
)
...
from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_state') }} stt
    join seq_lookup seq on seq.orcabus_id = stt.sequence_id
where {{ cdc_upper_bound('orcabus_sequence_run_manager', 'sequence_run_manager_state', 'stt._dms_cdc_timestamp') }}
{% if is_incremental() %}
  and (
      {{ cdc_window('orcabus_sequence_run_manager', 'sequence_run_manager_state', 'stt._dms_cdc_timestamp') }}
      or {{ cdc_window('orcabus_sequence_run_manager', 'sequence_run_manager_sequence', 'seq._dms_cdc_timestamp') }}
  )
{% endif %}
```

When joining multiple CDC source, the following applies:

- A lookup must be bounded to `pending` using `cdc_upper_bound`, not the window,
  as the state in the window can belong to something earlier that was outside
  the window. An inner join to a windowed lookup would have missed that state.
- A row must be read when any side changes. A row can become visible in any
  order, so the condition must compare any window using `cdc_window` that the
  resulting join depends on using an `or`.

Generally the join should depend on any models that could change it. For
example, `sat_workflow_run_detail` reprocesses a workflow run's rows when its
workflow definition changes.

### Reading an `int_cdc` model

The `int_cdc` models under `models/cdc/` are ephemeral, which means dbt inlines
them into each model that refers to them. These models give the current state of
a CDC table, or an association between tables. They shouldn't be windowed,
because joins sometimes need rows that don't change, for example, a new link
between an unchanged library and unchanged project.

Instead, each one has a `cdc_changed` column, which consumers filter on:

```sql
from {{ ref('int_cdc_mm_library_sample') }}
{% if is_incremental() %}
where cdc_changed
{% endif %}
```

For a current-state model, `cdc_changed` is true when the key's current row is
in the window. For an association, it is true when any side changed. So a
consumer doesn't need to know which tables are being used behind the model.

Most current-state models are a call to the `int_cdc_state` macro because they
all have the same shape. The association models compute `cdc_changed` inline, as
an `or` over the dependent sides.

### Reading another warehouse model

Use `load_bound`, as in `effsat_library_sample`:

```sql
from {{ ref('link_library_sample') }}
{% if is_incremental() %}
where {{ load_bound('load_datetime') }}
{% endif %}
```

This compares against the `max(load_datetime)` which ensures correct ordering
between warehouse models as they are processed.

`--vars '{"reread_from": "<timestamp>"}'` replaces the lower bound with that
time. The bound is strict, so give a time before the first row to reread.

### Adding a source or a model

1. Tag the source `cdc` in `models/cdc/_sources.yml` with `<<: *cdc_table`. A
   partitioned table also needs `cdc_partition_expression` in its `meta`, like
   `s3_object`.
2. Bound every read of the source with one of the macros above.
3. Make the model skip rows it already has, by merging on a key or with a
   `not exists` on the row's hash. Rereads happen after every incomplete run.
4. Run `dbt test` where `assert_cdc_sources_bounded` should fail if a read is
   unbounded.

## Operating the watermarks

At the end of a complete run, the logs show which CDC positions were updated.
Consider the following if anything needs fixing:

- To re-read a CDC source table, move the position back, or set to null to
  re-read from the start:

  ```sql
  update ops.cdc_watermark
  set position = '2026-09-15'
  where source_id = 'orcabus_workflow_manager.workflow_manager_state';
  ```

- To re-read a warehouse model, use `--vars '{"reread_from": "<timestamp>"}'`.
  This overrides the lower bound in the `load_bound` with the timestamp.
- If a change makes a model accept rows it used to skip, it would need to be
  re-read.
- If rows are ever deleted manually, the `position` won't automatically update.
  So if it's expected that these rows would need to be re-processed from the
  source, the `position` would need to go back to pick up any missed rows.
- Deleting the watermark table would have a similar effect to a full rebuild, as
  it would be recreated on the next run. This could be used as a way to
  reprocess every record without clearing the history.
- Avoid starting a run while another run is doing. While `pending_invocation_id`
  will keep the CDC positions safe, the `load_bound` assumes that runs don't
  overlap.
