# 4. CDC deletes: keep in the raw vault, end in the business vault

- Status: Accepted
- Date: 2026-10-26 (recorded 2026-11-26, after the fact, from the issues, PRs and warehouse
  meeting notes from 2026-10-05 to 2026-11-11)

## Context

In early October 2026, a sequencing run's SRM library associations carried malformed library IDs.
In the old warehouse they hit a foreign key and blocked the daily load, so the key was dropped.
The new warehouse loads without constraints, and flags upstream errors with dbt data tests instead.
Here, the relationship test between `link_library_sequencing_run` and `hub_library` failed
([orcahouse-project#66](https://github.com/umccr/orcahouse-project/issues/66)).

Two things made a proper fix harder:

- DMS did not write deletes (`CdcInsertsAndUpdates` was true), so an upstream delete never reached
  the warehouse ([orcahouse-project#65](https://github.com/umccr/orcahouse-project/issues/65)).
- Upstream Postgres uses the default replica identity, so a delete row carries only the primary
  key. The warehouse has to look back to find what was deleted.

Options considered:

- **Tolerate the failing test** (2026-10-14). Superseded on 2026-10-20: upstream data should be
  fixed upstream.
- **Insert the library into the hub by hand, or suppress it permanently in MDM** (2026-10-14).
  Superseded on 2026-10-20 by fixing the source.
- **Mark the associations inactive upstream.** Rejected: "inactive" is for records with
  downstream effects. These IDs should never have existed and nothing used them, so they were
  deleted.
- **Delete the unlinked rows from the link as a one-off.** Rejected: the raw vault would lose what
  the source said.
- **Stop tracking deletes and remove the rows.** Rejected in the #66 discussion: it loses history.
- **Add an `is_deleted` column to the raw vault.** Rejected: the raw vault stays close to the
  source and carries the CDC `op` as it arrives.
- **Filter deleted pairs out in a business vault link** (first proposal in #66). Replaced by an
  effectivity satellite, which also keeps when the link was effective.
- **Require `REPLICA IDENTITY FULL` upstream.** Not rejected: under investigation in the
  production V2 milestone. Until then the warehouse looks back.

## Decision

- Fix bad data upstream: delete it, and let DMS deliver the delete (`CdcInsertsAndUpdates` false,
  orcahouse PR #284). Upstream guard rails on library IDs follow separately.
- Feed `hub_library` from the SRM as well, taking library IDs as the source gives them, so every
  SRM link resolves.
- Keep deletes in the raw vault: hubs and links keep their keys, and the satellite records the
  `op = 'D'` row. Fill the delete row's columns from the previous row.
- End the relationship in a business vault effectivity satellite
  (`effsat_library_sequencing_run`), which marts read for current links. It is rebuilt per changed
  link with `delete+insert`, not `merge`, because a recomputed period can start at a different
  time.
- Scope it to SRM library associations only. Apply the pattern to other sources when a case
  appears. On 2026-11-11 this pattern was adopted as the playbook for failing data tests and
  invalid business keys.

Implemented in PR [#51](https://github.com/umccr/orcavault/pull/51) (2026-11-02). The behaviour
is specified in [openspec/specs/cdc-deletes](../../openspec/specs/cdc-deletes/spec.md). How it
is built is described in [cdc-deletes.md](../architecture/cdc-deletes.md).

## Consequences

- The build no longer fails on these associations, and the raw vault keeps a full audit of what
  upstream said and when it was deleted.
- Marts show only current associations, with no manual cleanup.
- Malformed library IDs stay in `hub_library` for good. That is by design.
- Delete rows need a look-back over the association history, until upstream sets
  `REPLICA IDENTITY FULL`.
- Deletes in every other CDC source are still ignored, until a change extends the pattern.

## References

Warehouse meeting notes in the knowledge base (private repository):

- [2026-10-05](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-10-05-warehouse.md): old warehouse foreign key dropped; new warehouse tests instead of constraints
- [2026-10-14](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-10-14-warehouse.md): failing link test tolerated for now
- [2026-10-20](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-10-20-warehouse.md): fix upstream: delete, enable DMS deletes, model the delete
- [2026-10-26](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-10-26-warehouse.md): hub library second source; delete ended in the business vault
- [2026-11-04](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-11-04-warehouse.md): model merged; `delete+insert`; `REPLICA IDENTITY FULL` to investigate
- [2026-11-11](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-11-11-warehouse.md): pattern adopted as the failing-data-test playbook
- [Warehouse Production Release](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Projects/warehouse-production-release.md): project log and key decisions
