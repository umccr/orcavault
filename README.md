# OrcaVault

For project documentation, please refer to https://github.com/umccr/orcahouse-doc

For data warehouse issue tracking, please submit an issue to https://github.com/umccr/orcahouse-project/issues

## Development

Create a Python virtual environment (any method) and install the dev toolchain [requirements](requirements.txt).

See [README_DEV.md](README_DEV.md) for more _comprehensive_ setup details.

```
conda activate orcavault
make install
make check
```

We need an authenticated AWS session as we are developing against the remote OrcaVault dev environment. 

Use your usual AWS CLI setup to authenticate.

For example:
```
export AWS_PROFILE=unimelb-warehouse-prod-poweruser
aws sso login
```

Source the [dx script](dx.sh). It exports shell functions (command shortcut) related to the remote OrcaVault dev environment.
```
source dx.sh
```

Connect to the dev warehouse. This makes the house key, the hosts entry, the tunnel and the dbt credentials.
```
house_up
```

Each step is also its own function: `house_key`, `house_host`, `house_tunnel`, `house_nc` and `house_cred`.
`house_down` closes the tunnel and clears the credentials.

Run the dbt debug command to check the connection.
```
dbt debug
```

You should expect to see a successful connection.
```
<...>
07:22:44  Registered adapter: redshift=1.10.1
07:22:47    Connection test: [OK connection ok]

07:22:47  All checks passed!
```

## Personal schema

You build in your own personal schema, named after your AWS SSO username, with a copy of each layer. For example,
`marko.malenic@<domain>` builds in `dev_marko_malenic_dcl`. Run `house_schema` to see yours, or set `ORCAVAULT_SCHEMA`
before `house_up` to pick another name, e.g. `export ORCAVAULT_SCHEMA=dev_marko`. The shared schemas belong to the
daily run.

It works like a git branch, with the dev daily run as its upstream. Any model you haven't built yourself comes
from the dev daily run's tables, and there are two ways to sync with it:

```
dbt_defer                    # fetch what the dev daily run built, and rebuild your changes on top of it
dbt_clone                    # the same, and also make a view of dev's table for every model you haven't changed
dbt_status                   # what you've changed, and whether dev has run since you last synced
dbt build -s hub_library+    # build your change and everything downstream of it
dbt_drop                     # drop your personal schema once you're done with it
```

With `dbt_defer`, your schema only has your changes, and dbt reads everything else from dev. With `dbt_clone`, your
schema has every model, so you can browse all of it in the Redshift query editor. Sync first, and again after each dev
run. See [README_DEV.md](README_DEV.md#personal-schemas) for how it works.

## dbt

The dbt has multiple targets. You can `dbt --help` for more details.

```
dbt debug
dbt clean
dbt deps
dbt compile
dbt build
dbt seed
dbt run
dbt test
```

You can run a specific model by name. Prefer selecting what you've changed, as a `dbt build` with no selection
builds every model from scratch into your personal schema.
```
dbt run -s hub_sequencing_run
```

Running the incremental model won't be updated upon the consecutive run. 
You can pass `--full-refresh` flag to reload from the beginning all over again.
BUT. Doing so will lose the model's historical `load_datetime` history.
```
dbt run -s hub_sequencing_run --full-refresh
```

The append-only ICA usage models ignore a project-wide `--full-refresh`, so a routine full refresh of the
project cannot silently discard their load history. A column added to a model's SQL is applied to the
existing table in place with `on_schema_change: append_new_columns`, so widening these models never needs a
rebuild. Rebuild them only when you mean it, naming them explicitly:

```
dbt run -s spreadsheet__ica_usage_report sat_workflow_run_ica_usage --vars '{ica_usage_full_refresh: true}'
```

This is lossless only while `tsa.spreadsheet__ica_usage_report` still carries every source row.

## Redshift

* Login to the Data Warehouse AWS account console using `AWSPowerUserAccess` role.
* Navigate to the Redshift QueryEditor v2.
* Select the `Serverless: orcahouse-dev` warehouse for development.
* On the connection prompt,
  * Select `Federated User`
  * Enter `orcavault` at database name
  * Click `Create Connection` button
