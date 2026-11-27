# CDC deletes

How a row deleted upstream flows through the warehouse. Today this applies only to the sequence
run manager (SRM) library associations. Other sources follow the same pattern when they need it.

The required behaviour is specified in
[openspec/specs/cdc-deletes](../../openspec/specs/cdc-deletes/spec.md), and why it is designed
this way is in decision record [0004](../decisions/0004-cdc-deletes-close-in-business-vault.md).

## The pattern

- **The raw vault keeps everything.** Hubs and links never lose a key because of a delete. The
  satellite records the delete as it arrives, with `op = 'D'`. No deleted flag is invented here.
- **The business vault ends it.** An effectivity satellite derives from the satellite's `op`
  when a relationship stops, and starts again.
- **Marts read only what is current.** They join through the effectivity satellite, so a delete
  upstream disappears from the marts while the history stays in the vault.

This lets bad data be fixed where it belongs, upstream, and the warehouse records both what the
source said and when it was removed.

## How a delete arrives

DMS writes an upstream delete as a CDC row with `op = 'D'`. Two things shape the design:

- DMS only writes deletes when `CdcInsertsAndUpdates` is false. This is set in the orcahouse
  infrastructure.
- OrcaBus Postgres tables use the default replica identity, so a delete row holds only the
  primary key, e.g. `orcabus_id`. The other columns are empty.

The warehouse therefore looks back. [`cdc_fill_delete`](../../macros/cdc_fill_delete.sql) fills
each empty column of a delete row from the latest earlier non-delete row with the same key, and
keeps any value the delete already has. If upstream ever sets `REPLICA IDENTITY FULL`, delete rows
carry every column and this look-back can go.

## Through the layers

| Layer | What happens to an SRM library association delete |
|---|---|
| CDC intermediate (`cdc/srm/`) | `int_cdc_srm_libraryassociation` keeps a delete as the association's latest state, with its `op` and the filled `library_id` and `sequence_id`. |
| Raw vault | `hub_library` also loads SRM library IDs, as the source gives them, so every association's library is in the hub. `link_library_sequencing_run` keeps the link. `sat_library_sequencing_run_srm` records the delete against that link. |
| Business vault | `effsat_library_sequencing_run` ends the link's effectivity; see the rules below. |
| Marts | `lims` reads only the links that are current in the effectivity satellite. `em_library_services` leaves out associations whose latest state is a delete. |

## Effectivity rules

`effsat_library_sequencing_run` decides when a library is on a sequencing run:

- An SRM link is effective while it has at least one association that is not deleted. A link can
  have more than one, e.g. a library on two sequences with the same instrument run.
- It ends when its last association is deleted, and a new period starts if one is created again.
- A link from any other source is always effective from its load time. Those sources are
  snapshots that don't delete. So is an SRM link with no rows in the satellite.
- Each link has at most one current row, which the marts rely on.

Each run recomputes the whole history of every link that is new or has a new satellite row, and
replaces that link's rows (`delete+insert`). It can't merge on `hash_diff` like the other
effectivity satellites: when an earlier association arrives late, a period can start at a
different time, and a merge would leave the period it replaces current. A period loaded before
keeps its `load_datetime`, so only its end changes.

## Scope

Only SRM library associations are handled. A delete in any other CDC source, including an SRM
sequence, still arrives from DMS but has no effect on effectivity or the marts. Extending the
pattern to another source is a change to the
[`cdc-deletes` spec](../../openspec/specs/cdc-deletes/spec.md).
