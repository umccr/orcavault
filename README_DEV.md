# Development

We expect the following dev tools to be installed and available in your system PATH. We provide [Brewfile](Brewfile) as an example on macOS and you can run `brew bundle` to install them. You can manage these dev tools in any other way as see fit for your local dev setup and suits to your OS.

Tools:
- Python3 _(pick your preferred way to manage the virtual environment)_
- dbt-core cli – https://github.com/dbt-labs/dbt-core
- aws-cli
- Makefile _(Optional `make` binary to execute [Makefile](Makefile) targets. You can directly call those commands and scripts, otherwise.)_
- dx.sh _(Optional [dx.sh](dx.sh) scripts.)_

Example:

From the project root directory, do like so.
```
conda create -n orcavault python=3.13
conda activate orcavault
pip3 install -r requirements.txt
```

Note that we use Python3 virtual environment (conda, uv, venv or any equivalent) for managing dbt-core cli and other commandline tools (if any). No Python development nor syntax familiarity is expected. We are SQL shop! See the next section.

## AWS Session

Use your usual way of AWS CLI setup to authenticate. Manage and switch authenticated session and AWS profile however you like. Be consistent with your setup in your way. You do not need to change that. Any README.md guideline "step" around AWS CLI authenticated session is just "an example" only. The step only _signals_ that you need to be authenticated at the point. How is – up to you.

## Personal schemas

Each developer builds OrcaVault in their own personal schemas, so nobody overwrites the shared dev tables or
another developer's work. The shared schemas, `psa`, `dcl`, `mart` and `seed`, are only built by the daily run in
[orcahouse/infra/orcavault-run](https://github.com/umccr/orcahouse/tree/main/infra/orcavault-run). The workflow
borrows its language from git:

| git           | OrcaVault                                                                    |
|---------------|------------------------------------------------------------------------------|
| `origin/main` | The tables the dev daily run built, e.g. `dcl.hub_library`.                  |
| your branch   | Your personal schemas, e.g. `dev_marko_dcl.hub_library`.                     |
| `git fetch`   | Download the dev daily run's dbt manifest to `target/upstream`.              |
| `git pull`    | `dbt_defer` or `dbt_clone`, which fetch, then rebuild your changes on top.   |
| `git status`  | `dbt_status`, your changes compared to dev, and whether dev has run since.   |

How it works:

- **Schemas.** `house_cred` sets `ORCAVAULT_SCHEMA`, the target schema in [profiles.yml](profiles.yml), from your
  AWS SSO username unless you've already set it. Everyone connects to Redshift as the same PowerUser database
  user, so the SSO username is what tells developers' schemas apart. The
  [generate_schema_name](macros/generate_schema_name.sql) macro prefixes each layer's schema with it, such as
  `dev_marko_dcl`. The daily run uses the target schema `public`, which builds the shared schemas instead.
- **Defer.** After every run, the daily run writes its dbt manifest to `state/manifest.json` in its results
  bucket, which `dbt_defer` and `dbt_clone` download. `house_cred` sets `DBT_DEFER` and `DBT_STATE`, so dbt reads
  any model you haven't built in your personal schema from the dev table, see
  [defer](https://docs.getdbt.com/reference/node-selection/defer). Until the first `dbt_defer` or `dbt_clone`, dbt
  stops with `Could not find manifest in --state path`, as it does after `dbt clean`, which also removes it.
- **Clone.** `dbt_clone` also makes a view of dev's table in your schema for each model you haven't changed, so
  your schema has every model, e.g. in the query editor. Redshift can't clone a table without copying its data, so
  these are views, and late-binding ones, see [macros/clone.sql](macros/clone.sql). The daily run rebuilds a table
  by renaming it and dropping it with `cascade`, which would also drop a normal view. The clone's `--full-refresh`
  replaces what's already in your schema with views, such as a table from earlier work you're no longer changing.
- **Keeping up with dev.** Dev's tables, and so the views and anything dbt defers to, change when the daily run
  finishes. Your own tables stay as they were when you built them. `dbt_status` says when dev has run since your
  last `dbt_defer` or `dbt_clone`. Run one of them again before you build, or the build mixes your older tables
  with dev's newer ones.
- **Watermark.** A personal build reads the daily run's `ops.cdc_watermark` and never writes it. Your models load
  CDC commits up to the same point as the dev tables they read from.
- **Full refresh.** `dbt_defer` and `dbt_clone` rebuild your changes with `--full-refresh`, and other builds don't
  unless you pass it. Between runs, the watermark's window only covers the last `cdc_position_margin_minutes` of the
  last run. After dev has run, an incremental build of a model in your schema misses everything between your last
  build and that window, without an error. To test a model's incremental path, build it again without
  `--full-refresh` before dev runs again.
- **Legacy sources.** A model rebuilt in your schema only reads its legacy sources with
  `--vars '{load_legacy: true}'`, which `dbt_defer` and `dbt_clone` pass on to their build, along with any other
  arguments. See the
  [initial load](https://github.com/umccr/orcahouse/blob/main/infra/orcavault-run/docs/initial-load.md).
- **Compute.** Everything you build counts towards the dev workgroup's monthly RPU-hour limit, which the daily run
  shares, so build only what you need.
- **Dropping.** `dbt_drop` drops every schema of your personal schema once you're done with it. Preview it with `dbt_drop --args '{dry_run: true}'`. It refuses to run against the daily run's
  schemas, and only drops the schemas dbt builds for your `ORCAVAULT_SCHEMA`, so check that it's yours. Nothing
  outside your schemas depends on them.

## Skills

Please do read all the documentation at https://github.com/umccr/orcahouse-doc

Dev:

- SQL (intermediate to advanced—CTE, CTAS, JOIN, WINDOW, PARTITION, RANK, ROW_NUMBER, CASE/WHEN, etc.)
- dbt
- PostgreSQL (data type, built-in functions, PL/pgSQL and stored procedure, view, trigger, etc.)
- Fundamental in database design and data modelling concepts 
  - relational data modelling / entity-relationship data modelling (ERD, 3NF, BCNF, FK, PK, UK, etc.)
- Data warehouse data modelling techniques
  - Data Vault 2.0 (Daniel Linstedt)
  - Dimensional Modelling (Ralph Kimball)


Infra:

- AWS (RDS Aurora, Redshift, Athena, Glue, ECS, Lambda, EC2, EventBridge)
- Datalake (S3)
- Terraform
- Git and GitHub
- Database Administration—DBA (query pref, tuning, backup, snapshot, proxy, tunnel, etc.)
- DataBricks, BigQuery (optionally building data mart layer when applicable)


IDE:

_note; recommendation only. leverage any other IDE combo as see fit for your productivity._

- VSCode
- JetBrains (PyCharm, DataGrip)
- DBeaver
- pgAdmin
- Oracle SQL Developer
- https://github.com/dineug/erd-editor
