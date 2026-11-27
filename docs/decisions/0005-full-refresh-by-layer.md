# 5. Full refresh by layer

- Status: Accepted
- Date: 2026-11-26 (builds on the warehouse meetings of 2026-10-20 and 2026-10-26)

## Context

A dbt `--full-refresh` drops an incremental table and rebuilds it from what its inputs hold now.
Every row gets the refresh time as its `load_datetime`. In a Data Vault that is a loss, not a
rebuild:

- The raw vault records what each source said and when the warehouse learned it. Its sources are
  not complete: the TSA is reloaded, and CDC is read through a watermark, so earlier states may no
  longer be readable.
- The PSA is the only history of sources that give no clean differentials, such as spreadsheets.
  The TSA behind it is truncated and reloaded.
- Hubs hold the core business keys. Their first `load_datetime` and record source are the audit
  anchor that every link and satellite hangs off.
- The business vault is derived from the raw vault, so it can be rebuilt from it at any time.

Until the production cut-off in early November 2026, full reloads were allowed. After it, history,
especially in hubs, is kept (2026-10-20). Routine full refreshes were also to be avoided, and
blocking them was to be considered (2026-10-26).

## Decision

In the shared and production schemas:

- The **business vault** (`models/dcl/business_vault/`) may be fully refreshed when business logic
  changes.
- The **raw vault** (`models/dcl/raw_vault/`) and the **PSA** (`models/psa/`) must not be fully
  refreshed. An exception needs a core maintainer's agreement first.
- **Hubs** should never need a full refresh. A change that seems to need one is redesigned.

Personal schemas are not covered: they are rebuilt from the shared schemas and hold no history of
their own.

The rules and how to apply them: [data-vault.md](../architecture/data-vault.md).

## Consequences

- Business logic can change freely in the business vault, which is rebuilt from history kept below.
- A change to raw vault or PSA logic is applied going forward, or repaired with targeted re-reads
  (moving a CDC watermark, `reread_from`), not by a rebuild.
- The rule is enforced only by review and by the agent rules in `AGENTS.md`, for now. dbt's
  `full_refresh: false` config could enforce it, as the ICA usage models already do with a
  variable. That needs its own change, because personal schemas and the one-off initial load still
  need full refreshes.

## References

Warehouse meeting notes in the knowledge base (private repository):

- [2026-10-20](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-10-20-warehouse.md): production cut-off; afterwards history, especially hubs, is kept
- [2026-10-26](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-10-26-warehouse.md): avoid routine full refreshes; consider blocking them
