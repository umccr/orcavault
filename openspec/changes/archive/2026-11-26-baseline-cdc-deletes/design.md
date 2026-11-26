# Design

## Context

This is a baseline. It records behaviour that is already in `main`; see proposal.md under Why.
The full description of how it is built is in
[docs/architecture/cdc-deletes.md](../../../../docs/architecture/cdc-deletes.md). The rationale and
the rejected options are in decision record
[0004](../../../../docs/decisions/0004-cdc-deletes-close-in-business-vault.md).

Where the behaviour lives:

- `macros/cdc_fill_delete.sql`: fills a delete row's columns from the previous non-delete row.
- `models/cdc/srm/int_cdc_srm_libraryassociation.sql`,
  `int_cdc_srm_libraryassociation_sequence.sql`: current association state, including deletes.
- `models/dcl/raw_vault/library/hub_library.sql`: SRM is a source of the hub.
- `models/dcl/raw_vault/library/sat_library_sequencing_run_srm.sql`: records each delete.
- `models/dcl/business_vault/library/effsat_library_sequencing_run.sql`: effectivity periods.
- `models/mart/centre/lims.sql`, `em_library_services.sql`: read only current associations.
- Tests: the unit tests in `tests/fixtures/deletes/deletes.yml`, and the `is_current = 1`
  uniqueness test on `effsat_library_sequencing_run`.

## Goals / Non-Goals

**Goals:**

- Capture the current delete behaviour as testable requirements.
- Give the next source that needs deletes a spec to modify.

**Non-Goals:**

- Handling deletes for any other source, or changing behaviour.
- Upstream changes (`REPLICA IDENTITY FULL`, library ID guard rails).

## Decisions

These are summaries. Decision record 0004 has the full reasoning.

- **Fix bad data upstream, and model the delete.** The malformed associations were deleted in
  the SRM, not marked inactive and not removed from the warehouse by hand.
- **Raw vault keeps everything; the business vault ends it.** Hubs and links keep the keys. The
  satellite records the CDC `op` as it arrives. An effectivity satellite derives the end.
- **The hub takes SRM library IDs as they come.** The link resolves through the hub, rather than
  by deleting unlinked rows from the link.
- **Fill delete rows by looking back**, because upstream uses the default replica identity.
- **`delete+insert`, not `merge`, for the effectivity satellite.** A period can start at a
  different time when it is computed again, and a merge on `hash_diff` would leave the replaced
  period current.
- **Narrow scope.** Only SRM library associations. The pattern is applied to other sources when
  they need it.

Layers affected: `cdc/` (SRM `int_cdc`), `dcl/raw_vault/library/`, `dcl/business_vault/library/`,
and `mart/centre/` (`lims`, `em_library_services`). Mart columns do not change. No full refresh
is needed, and load history is kept.

## Risks / Trade-offs

- [Look-back cost] Filling delete rows uses a window over the whole history of the association
  table → acceptable at the current table sizes. `REPLICA IDENTITY FULL` upstream would remove it.
- [Malformed keys in the hub] Malformed library IDs stay in `hub_library` for good → by design.
  The raw vault keeps what the source said, and marts read only current links.
- [Recompute cost] Each run recomputes the full history of every changed link → bounded to the
  links that changed.
- [Other sources] A delete anywhere else is ignored → see Open Questions.

## Open Questions

Candidates for follow-up changes. Each one would modify the `cdc-deletes` spec:

1. `REPLICA IDENTITY FULL` upstream, so delete rows carry every column and the look-back can go.
   Being investigated in the production V2 milestone.
2. Deletes for other CDC sources, starting with an SRM sequence, when a case appears.
