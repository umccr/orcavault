# Operating the CDC watermarks

> **For maintainers only.** These steps change `ops.cdc_watermark`, which the shared dev run
> uses. A personal schema never writes the watermarks; see
> [personal-schemas.md](personal-schemas.md).

How the watermark works is in [architecture/cdc-watermark.md](../architecture/cdc-watermark.md).

## Fixing the watermarks

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
- Avoid running dbt while DMS is doing a full load, e.g. after a "Reload target"
  or "Reload table data". Every reloaded row has the same commit time, so models
  in one run can see different rows and tests can fail.
- Avoid starting a run while another run is in progress, including one with
  `--select`. While `pending_invocation_id` will keep the CDC positions safe,
  the `load_bound` assumes that runs don't overlap.
