# 2. Spec-driven changes with OpenSpec

- Status: Accepted
- Date: 2026-11-26 (proposed 2026-11-24)

## Context

Developers use two coding agents, Kiro (`kiro-cli`) and Claude Code. We want a spec-driven
workflow in which both feel native, with specs owned by the repository rather than by one
agent. Options considered: Kiro specs, OpenSpec, GitHub Spec Kit and BMAD.

- Kiro specs are Kiro-native; Claude Code users would work inside another agent's process.
- Spec Kit is suited to greenfield work with heavier, gated phases.
- BMAD's role-based process is too heavy for per-repo work. It may suit higher-level project
  requirements and architecture, and is to be tried there.

On 2026-11-25 the warehouse team agreed to pilot OpenSpec in the technical warehouse repos and
revisit it if it doesn't work. OrcaVault was set up first, and two existing features were
captured as baseline changes, `cdc-watermark` and `cdc-deletes`.

## Decision

We use OpenSpec, initialised for both agents (`openspec init --tools kiro,claude`).

- In-flight work lives in `openspec/changes/<name>/`; archiving merges behaviour into
  `openspec/specs/`.
- Agent rules live in `AGENTS.md`, which Kiro loads natively and `CLAUDE.md` imports.
  `.kiro/steering/` holds pointers only.
- Long-lived context stays outside OpenSpec, in team-owned `docs/`: architecture in
  `docs/architecture/`, decisions in `docs/decisions/`.

How we work with it: [docs/dev/spec-driven.md](../dev/spec-driven.md).

## Consequences

- Both agents get the same OpenSpec skills and read the same specs.
- Features and bugfixes share one change layout by default; telling them apart needs a
  convention (folder prefix or a custom schema).
- Specs are plain Markdown in Git, so a later move to another framework (e.g. Spec Kit)
  changes the workflow wrapper, not the content.

## References

- [Warehouse meeting 2026-11-25](https://github.com/umccr/management-knowledgebase/blob/main/PlatformServices/Meetings/Project/2026-11-25-warehouse.md)
  (knowledge base, private repository): framework comparison and the decision to pilot OpenSpec.
