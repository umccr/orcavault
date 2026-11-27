# 1. Record architecture decisions

- Status: Accepted
- Date: 2026-11-24

## Context

Design reasoning was scattered across README files, docs and pull requests, and was easy to
lose. OpenSpec changes are point-in-time and are archived after delivery.

## Decision

We record architecturally significant decisions as ADRs in `docs/decisions/`, named
`NNNN-title.md`, using the [template](0000-template.md).

- An accepted ADR is not edited. A later ADR supersedes it, and the old one's status is
  updated to point to the new one.
- A change that delivers a real decision promotes it to an ADR (see
  [docs/README.md](../README.md)).

## Consequences

- The reasoning behind a decision survives the change that produced it.
- Each decision costs a short document to write.
