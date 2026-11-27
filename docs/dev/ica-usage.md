# ICA Usage

The append-only ICA usage models ignore a project-wide `--full-refresh`, so a routine full refresh of the project cannot
silently discard their load history. A column added to a model's SQL is applied to the existing table in place with
`on_schema_change: append_new_columns`, so widening these models never needs a rebuild. Rebuild them only when you mean
it, naming them explicitly:

```
dbt run -s spreadsheet__ica_usage_report sat_workflow_run_ica_usage --vars '{ica_usage_full_refresh: true}'
```

This is lossless only while `tsa.spreadsheet__ica_usage_report` still carries every source row.
