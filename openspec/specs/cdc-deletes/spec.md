# cdc-deletes Specification

## Purpose

Upstream deletes in a CDC source are kept as history in the raw vault, and end a relationship's
effectivity in the business vault. Marts then show only what is current upstream, and the
warehouse can still say when, and what, was deleted.

## Requirements

### Requirement: Deletes arrive as CDC rows
The warehouse SHALL receive an upstream delete as a CDC row with `op = 'D'` in the source table.
This depends on DMS writing deletes (`CdcInsertsAndUpdates` set to false). A delete row MAY
carry only the primary key, because upstream Postgres tables use the default replica identity.

#### Scenario: Delete of an association
- **WHEN** an SRM library association is deleted upstream
- **THEN** its source table gets a row with `op = 'D'`, the association's `orcabus_id`, and the commit time

### Requirement: Delete rows are filled from the previous row
For a delete row, the warehouse SHALL fill each missing column from the latest earlier non-delete
row with the same primary key. A value the delete row already has SHALL be kept. Non-delete rows
SHALL be unchanged.

#### Scenario: Delete with only the key
- **WHEN** a delete row has only `orcabus_id`, and an earlier insert of that key has `library_id` = `L_A` and `sequence_id` = `seq_1`
- **THEN** the delete is read with `library_id` = `L_A` and `sequence_id` = `seq_1`

#### Scenario: Delete with the full row
- **WHEN** a delete row already carries `library_id`
- **THEN** that value is used, not the earlier row's

#### Scenario: Insert and delete at the same time
- **WHEN** an insert and a delete of the same key have the same commit time
- **THEN** the delete is ordered after the insert, so the association's latest state is deleted

### Requirement: Current association state includes deletes
The current state of each SRM library association SHALL be its latest row up to the watermark,
including a delete row. Its `op` SHALL be kept, so that a consumer can tell the association has
ended.

#### Scenario: Latest row is a delete
- **WHEN** an association's latest row is a delete
- **THEN** its current state has `op = 'D'`, with the filled `library_id` and `sequence_id`

### Requirement: The raw vault keeps deleted keys and records the delete
A delete SHALL NOT remove a business key from a hub, or a relationship from a link. The SRM
library and sequencing run satellite SHALL record the delete as a row with `op = 'D'`, keyed by the
link of the association it deleted. The raw vault SHALL NOT derive a deleted flag of its own.

#### Scenario: Association deleted
- **WHEN** an SRM library association is deleted upstream
- **THEN** `hub_library` and `link_library_sequencing_run` keep their rows, and `sat_library_sequencing_run_srm` gets a row with `op = 'D'` for that link

### Requirement: SRM libraries are loaded into the library hub
`hub_library` SHALL load the library IDs of SRM library associations as well as those from its
other sources. Each library ID SHALL be taken as the source gives it, even if it is malformed. Every
SRM library and sequencing run link then resolves to a library in the hub.

#### Scenario: Library only known to the SRM
- **WHEN** an SRM association refers to a library ID that no other source has
- **THEN** that library ID is in `hub_library` with record source `orcabus_sequence_run_manager`, and the link's relationship test passes

### Requirement: SRM links are effective while they have an association
`effsat_library_sequencing_run` SHALL keep a link from the SRM effective while it has at least one
association that is not deleted. It SHALL end the link when its last association is deleted, and
start a new period if an association is created again.

#### Scenario: Last association deleted
- **WHEN** a link's only association is created on day 1 and deleted on day 3
- **THEN** the link has one period from day 1 to day 3, and it is not current

#### Scenario: One of two associations deleted
- **WHEN** a library is on two sequences with the same instrument run, and one association is deleted
- **THEN** the link stays effective

#### Scenario: Association created again
- **WHEN** a link's association is deleted on day 2 and created again on day 3
- **THEN** the link has a closed period ending on day 2, and a current period from day 3

### Requirement: Links without SRM deletes are always effective
A link from another source SHALL be effective from its load time with no end, because those
sources are snapshots that do not delete. So SHALL an SRM link that has no rows in the satellite.

#### Scenario: Legacy link
- **WHEN** a link comes from a legacy source
- **THEN** it is current from its `load_datetime`, even if an SRM delete exists for the same library and run

### Requirement: Effectivity is recomputed per changed link
Each run SHALL recompute the whole effectivity history of every link that is new or has a new SRM
satellite row, and replace that link's rows. A period that was already loaded SHALL keep its
`load_datetime`. Each link SHALL have at most one current row.

#### Scenario: Delete since the last run
- **WHEN** a link's current period was loaded in an earlier run, and its last association is deleted since then
- **THEN** that period gets an end time and stops being current, with its original `load_datetime`

#### Scenario: Late association
- **WHEN** an earlier association of a link arrives after its periods were computed
- **THEN** the periods are recomputed and replaced, and no stale current period is left

### Requirement: Marts show only current associations
The `lims` mart SHALL read library and sequencing run links only while they are current in
`effsat_library_sequencing_run`. When `em_library_services` lists the libraries known to the SRM,
it SHALL leave out associations whose latest state is a delete.

#### Scenario: Deleted association
- **WHEN** the only association between a library and a sequencing run is deleted upstream
- **THEN** `lims` no longer joins that library to that run, and the raw vault still holds the history

### Requirement: Deletes are handled only for SRM library associations
Deletes SHALL be modelled only for SRM library associations. A delete in any other CDC source,
including an SRM sequence, SHALL have no effect on effectivity or marts until a change extends this
capability to it.

#### Scenario: Sequence deleted
- **WHEN** an SRM sequence is deleted upstream
- **THEN** no effectivity period ends because of it
