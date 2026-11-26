# UNLOAD schema

Unloading a schema to S3 is implemented as a stored procedure via dbt macros in
[macros/procedures/](../../macros/procedures/). See for more details -
https://github.com/umccr/orcahouse-project/issues/94

## Deploy

The [orcavault-run](https://github.com/umccr/orcahouse/tree/main/infra/orcavault-run#the-unload) daily run calls the
procedure but doesn't deploy it, so its owner redeploys it after a change. Each deploy grants EXECUTE on it to the
`orcavault_builder` role.

```
dbt run-operation deploy_unload_schema
```

## Run

```
dbt run-operation run_unload_schema --args \
  '{"schema_name": "mart", "s3_bucket_path": "", "iam_role_arn": ""}'
```

## Onboarding

To call the stored procedure manually from the Redshift Query Editor, see
https://github.com/umccr/orcahouse-project/issues/35
