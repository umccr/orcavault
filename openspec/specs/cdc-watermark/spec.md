# cdc-watermark Specification

## Purpose

Incremental models load each CDC source row exactly once in effect. A row is never lost
because it became visible late, and re-reading a row is harmless. The warehouse keeps its own
record of how far it has read each CDC source table.

## Requirements

### Requirement: One watermark per CDC source table
The warehouse SHALL keep one watermark row in `ops.cdc_watermark` for each source tagged `cdc`.
The row is keyed by `<source_name>.<table_name>` and holds a `position` (the lower bound already
processed) and a `pending` (the upper bound of the current or last run). Models SHALL NOT keep
watermark state of their own.

#### Scenario: New CDC source is registered
- **WHEN** a run starts and a `cdc`-tagged source has no watermark row
- **THEN** a row is added for it with a null `position`

#### Scenario: Two sources move independently
- **WHEN** source A gets commits every hour and source B gets none for a week
- **THEN** A's position advances with each complete run, while B's stays at its last commit without holding A back

### Requirement: Pending is fixed at run start
At the start of a `dbt run` or `dbt build`, the warehouse SHALL set `pending` to the newest
visible commit time (`_dms_cdc_timestamp`) of each CDC source table that the run's selected
models read. Each such row SHALL be stamped with the run's invocation id. Rows for tables that
the run does not read SHALL be left unchanged.

#### Scenario: Partial selection records only what it reads
- **WHEN** a run selects models that read only source A
- **THEN** only A's `pending` and invocation id are updated, and every other row is unchanged

#### Scenario: Other dbt commands do not touch pending
- **WHEN** `dbt test`, `dbt compile` or `dbt docs generate` runs
- **THEN** no `pending` value changes

### Requirement: Models read a bounded window
A model that reads a CDC source SHALL bound its read by the table's watermark. Incrementally,
it reads rows committed after `position` and at or before `pending`. When not incremental, it
reads every row at or before `pending`. A null `position` means no lower bound, and a null
`pending` means no upper bound.

#### Scenario: Incremental read
- **WHEN** an incremental model runs with `position` = 10:00 and `pending` = 12:00
- **THEN** it reads rows committed after 10:00 and up to and including 12:00

#### Scenario: Row committed during the run
- **WHEN** a row with commit time 12:05 becomes visible while a run with `pending` = 12:00 is in progress
- **THEN** no model in that run reads it, and the next run does

#### Scenario: First build
- **WHEN** a model is built for the first time or with `--full-refresh`
- **THEN** it reads all rows up to `pending`

### Requirement: Every model in a run sees the same rows
All models in one run that read the same CDC source table SHALL use the same `pending` as
their upper bound. A downstream model then never sees a source row that its upstream model did
not see.

#### Scenario: Late model in a long run
- **WHEN** DMS writes new rows to a source while a run is in progress
- **THEN** models built late in the run read the same set of rows as models built early

### Requirement: Position advances only when every reader succeeds
At the end of a `dbt run` or `dbt build`, a table's `position` SHALL move to `pending` minus
`cdc_position_margin_minutes` (default 10). This happens only if every model that reads the
table succeeded in the same invocation that set `pending`. Otherwise the position SHALL stay,
and the next run reads the window again.

#### Scenario: All readers succeed
- **WHEN** every reader of source A succeeds, and `pending` = 12:00 with the default margin
- **THEN** A's position becomes 11:50

#### Scenario: One reader fails
- **WHEN** one reader of source A fails or is skipped
- **THEN** A's position is unchanged, while sources whose readers all succeeded still advance

#### Scenario: Selection misses a reader
- **WHEN** a run with `--select` builds some, but not all, readers of source A
- **THEN** A's position is unchanged

#### Scenario: Another invocation set pending
- **WHEN** a run ends but a later invocation has since overwritten a table's `pending`
- **THEN** that run does not move the table's position

#### Scenario: Source has no visible commits
- **WHEN** a table's `pending` is null at the end of a complete run
- **THEN** its existing `position` is kept, not cleared

### Requirement: Readers include inlined parents
A model SHALL count as a reader of a CDC source when it reads the source directly, or through
ephemeral or view models, followed recursively. A parent model that stores its own rows SHALL
NOT pass its sources on to the models that read it.

#### Scenario: Reader through an ephemeral model
- **WHEN** a satellite selects from an ephemeral `int_cdc` model that reads source A
- **THEN** the satellite is a reader of A, and A's position waits for it

#### Scenario: Downstream of a stored model
- **WHEN** an effectivity satellite reads a link table that is built from source A
- **THEN** the effectivity satellite is not a reader of A

### Requirement: Re-reading is harmless
Every incremental model that reads a CDC source SHALL skip rows it already holds, by merging on
a key or by checking the row's hash. A window that is read twice, because of the margin or a
failed run, SHALL then produce no duplicate rows.

#### Scenario: Margin overlap
- **WHEN** the next run re-reads the last 10 minutes of commits
- **THEN** rows that are already loaded are not inserted again

### Requirement: Changed flag for current-state models
An intermediate CDC model that gives a table's current state or an association SHALL read every
row up to `pending`, not only the window. It SHALL expose a `cdc_changed` flag that is true when
the key's current row, or any side of the association, is in the window.

#### Scenario: New link between unchanged entities
- **WHEN** an association row changes, and the two entities it links do not
- **THEN** the association is flagged `cdc_changed` and still joins to both entities

### Requirement: Warehouse-to-warehouse reads use load time
A model that reads another warehouse model SHALL bound its incremental read by load time: rows
with `load_datetime` after its own `max(load_datetime)`. It SHALL NOT compare commit time with
load time. The `reread_from` variable SHALL replace that lower bound, for repair.

#### Scenario: Normal incremental read
- **WHEN** an effectivity satellite runs incrementally
- **THEN** it reads parent rows with `load_datetime` after its own latest `load_datetime`

#### Scenario: Repair with reread_from
- **WHEN** a run passes `--vars '{"reread_from": "<timestamp>"}'`
- **THEN** the model reads parent rows with `load_datetime` after that timestamp

### Requirement: Unbounded CDC reads are rejected
Reading a CDC source through the watermark SHALL fail at compile time if the source is not
tagged `cdc`. The data tests SHALL fail if a model reads an `orcabus_*` source without a
watermark bound for it.

#### Scenario: Untagged source
- **WHEN** a model bounds its read of a source that is not tagged `cdc`
- **THEN** compilation fails with an error naming the source

#### Scenario: Missing bound
- **WHEN** a model reads an `orcabus_*` source without bounding it
- **THEN** `assert_cdc_sources_bounded` fails and names the model and source

### Requirement: Runs that must not move watermarks
A run SHALL NOT create, update or advance any watermark when it targets a personal schema.
A run SHALL NOT advance positions when it loads legacy data (`load_legacy`) or runs with
`--empty`.

#### Scenario: Personal schema build
- **WHEN** a developer runs `dbt build` against their personal schema
- **THEN** `ops.cdc_watermark` is unchanged, and the build reads the watermark that the shared run left

#### Scenario: Empty run
- **WHEN** a run uses `--empty`
- **THEN** no position advances

### Requirement: Watermarks are never in the future
`position` and `pending` SHALL never be later than the current time. The data tests SHALL fail
if either is.

#### Scenario: Future watermark
- **WHEN** a watermark row has `position` or `pending` later than now
- **THEN** `assert_cdc_positions_valid` fails and lists the row

### Requirement: Manual re-read by moving the position
Operators SHALL be able to re-read a CDC source by moving its `position` back, or by setting it
to null to re-read from the start. History already loaded is kept.

#### Scenario: Position moved back
- **WHEN** an operator sets a source's `position` to an earlier time
- **THEN** the next shared run reads that source from the new position, and re-read rows are deduplicated
