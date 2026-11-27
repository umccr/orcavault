# Proposal

## Why

Upstream deletes are already handled, but only for the sequence run manager (SRM) library
associations, and that behaviour has no spec. It shipped in PR
[#51](https://github.com/umccr/orcavault/pull/51) (2026-11-02). It depends on DMS delivering
deletes, which was turned on in
[orcahouse-project#65](https://github.com/umccr/orcahouse-project/issues/65). This baseline
records the current behaviour as the `cdc-deletes` spec, so that extending deletes to other
sources can be written as changes against it.

This change is retrospective: **no code changes**. The problem it solved is
[orcahouse-project#66](https://github.com/umccr/orcahouse-project/issues/66). Malformed library
associations from one sequencing run failed the daily relationship test between
`link_library_sequencing_run` and `hub_library`. They were deleted upstream, and the warehouse had
to model the delete without losing history.

## What Changes

- Adds the `cdc-deletes` spec, describing the behaviour as it is in `main` today.
- Adds decision record [0004](../../../../docs/decisions/0004-cdc-deletes-close-in-business-vault.md)
  with the design rationale and the rejected options.
- Renames `docs/architecture/srm-deletes.md` to `cdc-deletes.md`, restructures it around the
  pattern, and links it to the spec and the decision record.
- No change to models, macros or tests.

## Capabilities

### New Capabilities

- `cdc-deletes`: how upstream deletes in a CDC source flow through the warehouse. Covers filling
  delete rows, keeping them in the raw vault, ending effectivity in the business vault, and what
  the marts show. Today it applies only to SRM library associations.

### Modified Capabilities

None. Delete rows are read through the existing `cdc-watermark` bounds, whose behaviour does not
change.

## Impact

- Code: none. The behaviour lives in `macros/cdc_fill_delete.sql`, the SRM `int_cdc` models,
  `hub_library`, `sat_library_sequencing_run_srm`, `effsat_library_sequencing_run`, and the
  `lims` and `em_library_services` marts.
- Docs: `docs/architecture/cdc-deletes.md` (renamed from `srm-deletes.md`, restructured),
  `docs/decisions/` (adds 0004).
- Later changes that add deletes for another source must modify this spec.
