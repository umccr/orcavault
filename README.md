# OrcaVault

<!-- Landing page only, capped at 60 lines by a pre-commit hook. Do not add content here: put a
     new how-to or note in its own docs/dev/<topic>.md and add one line to the Index in docs/README.md. -->

The data warehouse dbt project.

For project documentation, please refer to https://github.com/umccr/orcahouse-doc

For data warehouse issue tracking, please submit an issue to https://github.com/umccr/orcahouse-project/issues

## Quickstart

Most of us develop with an agent (Claude Code or Kiro), in our own personal schema.

1. **Set up and connect** (you run this; it is interactive):

   ```
   python3 -m venv .venv && source .venv/bin/activate
   make install && make check

   export AWS_PROFILE=unimelb-warehouse-prod-poweruser
   aws sso login                             # any AWS login method

   source dx.sh && house_up                  # tunnel, credentials, personal schema
   dbt deps                                  # once per clone, and after dbt clean
   dbt_defer                                 # sync with the dev daily run
   ```

   Details and the daily loop: [docs/dev/personal-schemas.md](docs/dev/personal-schemas.md).

2. **Make a change** with your agent, spec first:
   [docs/dev/spec-driven.md](docs/dev/spec-driven.md).

## Redshift

To query the dev warehouse in a browser:

1. Log in to the Data Warehouse AWS account console with the `AWSPowerUserAccess` role.
2. Open Redshift Query Editor v2.
3. Select the `Serverless: orcahouse-dev` warehouse.
4. In the connection prompt, select `Federated User`, enter `orcavault` as the database name,
   and click `Create Connection`.

## Documentation

See [docs/](docs/README.md) for setup, architecture, how-to guides and decision records.
