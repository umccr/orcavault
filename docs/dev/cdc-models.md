# Writing CDC models

How to bound the reads of an incremental model, so it uses the CDC watermark. How the
watermark works, and what each bound macro does, is in
[architecture/cdc-watermark.md](../architecture/cdc-watermark.md), under
[The bound macros](../architecture/cdc-watermark.md#the-bound-macros).

## Reading one CDC table

Use `cdc_bound`, as in `sat_library_mm`:

```sql
from {{ source('orcabus_metadata_manager', 'app_library') }}
where {{ cdc_bound('orcabus_metadata_manager', 'app_library') }}
```

A satellite like this picks each key's latest row from the window. This window
holds every commit since the last run, meaning that a key's latest row in the
window is also its latest row overall.

## Joining multiple CDC tables

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

## Reading an `int_cdc` model

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

## Reading another warehouse model

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

## Adding a source or a model

1. Tag the source `cdc` in `models/cdc/_sources.yml` with `<<: *cdc_table`. A
   partitioned table also needs `cdc_partition_expression` in its `meta`, like
   `s3_object`.
2. Bound every read of the source with one of the macros above.
3. Make the model skip rows it already has, by merging on a key or with a
   `not exists` on the row's hash. Every run re-reads the last few minutes, and
   an incomplete run means the next one re-reads everything since `position`.
4. Run `dbt test` where `assert_cdc_sources_bounded` should fail if a read is
   unbounded.
