# Architecture decision records

**ADR** stands for _Architecture Decision Record_: a short note of one significant decision,
why it was made, and what it changes. Each file in this folder is one ADR.

Use [0000-template.md](0000-template.md). Accepted ADRs are not edited; supersede them with a
new one and update the old one's status to point to it.

## When to write an ADR

Keep the bar high. Write one only when the decision is hard or costly to reverse **and**
someone will plausibly ask "why?" later.

Write an ADR for:

- Modelling approach: layers, Data Vault patterns, how history and deletes are kept.
- Loading strategy: incremental vs full refresh, CDC watermarks, source integration.
- Platform and tooling choices: warehouse engine, dbt adapter, major upgrades.
- Cross-cutting behaviour: schema naming, personal schemas, mart contracts, access.
- Deliberately rejected or deferred options that people will keep suggesting.

Do not write an ADR for:

- Details of one model or change. They stay in the OpenSpec change.
- Anything easily changed in a single PR without wider impact.
- Naming, formatting or style. Those belong in `AGENTS.md`.
- Recipes or current behaviour. Those belong in `docs/` or `openspec/specs/`.

Quick test: if you cannot name a realistic alternative that was considered, it is probably
not an ADR.

## How

- Copy the template, take the next number, and name the file `NNNN-short-title.md`.
- Keep it short: Context, Decision, Consequences. Link instead of repeating other docs.
- Do not invent history. If the reasoning is reconstructed, say so in the text.
- Add a row to the index below in the same change.
- Reversing a decision means a new ADR that supersedes the old one. Never edit an accepted one.

## Index

Status values: Proposed, Accepted, Superseded by NNNN.

| #    | Decision                                                                 | Status   |
|------|--------------------------------------------------------------------------|----------|
| 0001 | [Record architecture decisions](0001-record-architecture-decisions.md)   | Accepted |
| 0002 | [Spec-driven changes with OpenSpec](0002-adopt-openspec.md)               | Accepted |
| 0003 | [CDC watermark table, one row per source table](0003-cdc-watermark-per-source-table.md) | Accepted |
| 0004 | [CDC deletes: keep in the raw vault, end in the business vault](0004-cdc-deletes-close-in-business-vault.md) | Accepted |
| 0005 | [Full refresh by layer](0005-full-refresh-by-layer.md) | Accepted |
