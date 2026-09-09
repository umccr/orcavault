# OrcaVault

For project documentation, please refer to https://github.com/umccr/orcahouse-doc

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

Make the house key and tunnel.
```
houseRule
houseKey
houseHost
houseTunnel
houseStatus
```

Make the house credentials.
```
houseCred
```

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

You can run a specific model by name.
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
project cannot silently discard their load history. New columns are added in place with
`on_schema_change: append_new_columns` instead. Rebuild them only when you mean it, naming them explicitly:

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
