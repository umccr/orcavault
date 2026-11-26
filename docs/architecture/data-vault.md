# Data Vault rules

OrcaVault's production rules for its Data Vault layers. General modelling guidance is in
[orcahouse-doc](https://github.com/umccr/orcahouse-doc); this page holds only the rules specific
to running OrcaVault. Add new rules as their own section.

## Rebuilding layers

A `--full-refresh` gives every row the refresh time as its `load_datetime`, and keeps only what
the inputs hold now. Below the business vault, that history cannot be rebuilt. Why:
[decision 0005](../decisions/0005-full-refresh-by-layer.md).

In the shared and production schemas:

| Layer | Folder | Full refresh |
|---|---|---|
| Business vault | `models/dcl/business_vault/` | Allowed when business logic changes |
| Raw vault | `models/dcl/raw_vault/` | Prohibited. Consult a core maintainer first. |
| Hubs (raw vault) | `models/dcl/raw_vault/**/hub_*` | Never needed. Redesign the change instead. |
| PSA | `models/psa/` | Prohibited. Consult a core maintainer first. |

- Always name what you refresh. Never run a project-wide `--full-refresh`.
- To refresh the business vault after a logic change, select it by path, e.g.
  `dbt build -s path:models/dcl/business_vault/library --full-refresh`. See
  [shared-schemas.md](../dev/shared-schemas.md#full-refresh) for building in the shared schemas.
- To repair raw vault rows, re-read instead of rebuilding: move the CDC watermark back, or use
  `reread_from` ([cdc-watermark-ops.md](../dev/cdc-watermark-ops.md)).
- Personal schemas are not covered. `dbt_defer` and `dbt_clone` rebuild your changes with
  `--full-refresh` there by design.
- The ICA usage models ignore a project-wide full refresh already
  ([ica-usage.md](../dev/ica-usage.md)).

## Modelling order

Model the raw vault from the business keys outwards:

1. **Hubs** first: one per business entity, keyed on its business key (see below).
2. **Links** next: one per relationship between hubs. A link between two hubs is always
   many-to-many. A link is always an association table. It records that a relationship
   existed, not when it ended; an effectivity satellite tracks that (see
   [cdc-deletes.md](cdc-deletes.md)).
3. **Satellites** last, attached to a hub or a link; a satellite has exactly one parent. It holds
   the descriptive values of its parent, and their history.

## Hubs: model the business key

A hub is keyed on a **business key**: the identifier the business itself uses for the entity,
such as `library_id` in `hub_library` or `sequencing_run_id` (the instrument run ID) in
`hub_sequencing_run`. Keying on the business key, and keeping one hub per business concept, is
the heart of the method. Finding the business key is a requirements step, done before any SQL.

- Do not key a hub on a technical ID: a serial ID, a UUID, a ULID such as `orcabus_id`, or an upstream
  primary key. Those mirror one source system's tables, not the business, and the hub breaks
  when that system changes.
- A generated ID can still be the business key if the business uses it, as `portal_run_id` is
  in `hub_workflow_run`.
  The test is whether people use and understand it, not how it was made.
- Ask what the business wants to track over time in the warehouse, and why it is valuable.
- Test the key with people: would at least three groups across the business, upstream and
  downstream (for example the lab, the source system owners and the analysts), recognise it and
  mean the same thing by it, as they do with `library_id`? If not, it is probably not the
  business key.
- One hub can load the same business key from several sources, if every source means the same
  thing by it. `hub_library` loads from Metadata Manager, the SRM and the spreadsheets. Each
  source's library is the same business concept, so the hub merges them into one row per
  `library_id`.
- Technical IDs still belong in satellites, as attributes that trace a row back to its source.

When unsure, read the Data Vault 2.0 guidance on business keys (Linstedt and Olschimke,
_Building a Scalable Data Warehouse with Data Vault 2.0_), or ask a maintainer before modelling
the hub. A hub is the hardest model to change later; see
[Rebuilding layers](#rebuilding-layers).
