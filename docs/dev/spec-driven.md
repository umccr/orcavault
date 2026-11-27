# Spec-driven development

We specify changes before building them. The framework is OpenSpec
([decision 0002](../decisions/0002-adopt-openspec.md)); the rest of this page is how we use it.

## Quickstart

New here, with only Claude Code or Kiro? Start in the repo root, on a branch.

1. **Install the CLI.** `brew bundle` installs `openspec` from the [Brewfile](../../Brewfile).
   For dbt and the warehouse connection, follow the
   [README Quickstart](../../README.md#quickstart).

2. **Start your agent** (`claude` or `kiro-cli chat`). It loads `AGENTS.md`, the repo rules, by
   itself.

3. **See what the warehouse already promises.** Run `openspec list --specs`, then ask the agent:

   > Explain the cdc-watermark spec in plain words.

4. **Think before you build.** Describe your idea and ask:

   > openspec explore: I want to add X. What would it touch?

   Or, for a fix, point it at what you already know:

   > openspec explore: I want to fix X. Read the failure analysis done with the Root Cause
   > Analysis agent, in the note at .local/input_rca_note.txt.

   Or start from an issue:

   > openspec explore: read https://github.com/umccr/orcahouse-project/issues/NN, including its
   > comments. What would it touch?

5. **Propose the change.**

   > openspec propose: add X

   This creates `openspec/changes/<name>/` with a proposal, design, spec changes and tasks. Read
   them, and edit or ask for changes until they are right. If a maintainer should agree before
   you build, open a draft PR with just the change folder and get it reviewed first. Do this for
   anything that touches the raw vault or PSA, mart columns, or an existing spec. Small,
   self-contained fixes can go straight on.

6. **Build it.**

   > openspec apply

   The agent works through `tasks.md` and ticks each task off. You validate in your personal
   schema ([personal-schemas.md](personal-schemas.md)).

7. **Finish.**

   > openspec archive

   The spec changes merge into `openspec/specs/`. Update `docs/` and add a decision record if
   the change needs one (see below), then raise a PR.

In Claude Code you can also type the skills as commands, e.g. `/openspec-propose`.

## OpenSpec drill

Try OpenSpec without leaving anything behind. Just enter the following lines one-by-one into your 
agent prompt and have a chat.

```
openspec new change tek1
openspec status --change tek1
openspec instructions proposal --change tek1
openspec list --specs
openspec show cdc-watermark --type spec
rm -rf openspec/changes/tek1
```

## Agents

- Two agents are supported: Kiro (`kiro-cli`) and Claude Code. Neither owns the process.
- Both agents get the same skills: `/openspec-propose`, `/openspec-apply-change`,
  `/openspec-archive-change` (plus `explore`, `update-change`, `sync-specs`).
- Agent rules live only in `AGENTS.md`. Kiro loads it natively (verified with kiro-cli
  3.6.1); `CLAUDE.md` imports it. `.kiro/steering/overview.md` only inlines
  `docs/architecture/README.md` via `#[[file:...]]`. Do not add rules to steering.
- OpenSpec project context and per-artifact rules: `openspec/config.yaml`.
- Telemetry: OpenSpec telemetry is off for Claude Code via `.claude/settings.json`. Elsewhere
  run `openspec config set telemetry.enabled false` once per machine.

## Where things live

OpenSpec covers only behaviour and the change in flight. A change's `design.md` is frozen when
the change is archived, so long-lived context lives outside OpenSpec:

| Question | Home |
|---|---|
| What must it do? | `openspec/specs/` (living, updated only by archiving a change) |
| How is it built now? | `docs/architecture/` (living, updated in the same change) |
| Why this way? | `docs/decisions/` (one record per real decision) |
| What did one change do? | `openspec/changes/archive/` (history, not maintained) |

When archiving, promote structural outcomes to `docs/architecture/` and decisions to
`docs/decisions/`. See [docs/README.md](../README.md).

## Existing features: baseline changes

A feature built before OpenSpec gets a retrospective baseline change before anyone changes it:

- The change records current behaviour only. It changes no code, and all its tasks are done.
- Write the spec from the code and tests, not from memory or old docs.
- Put the rationale in a decision record, citing the issues, PRs and meeting notes. Say that it
  was recorded after the fact.
- Archive it. Later work then modifies the living spec instead of rewriting docs.

Examples: `cdc-watermark` and `cdc-deletes` in `openspec/changes/archive/`.
