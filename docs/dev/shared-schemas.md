# Shared schemas

> **This is the exception, not the default.** It is for maintainers who need to fix the shared
> dev schemas directly. If you are developing a change, use a
> [personal schema](personal-schemas.md) instead.

This page explains how to build straight into the shared dev schemas (`psa`, `dcl`, `mart`,
...). The dev daily run builds these schemas, and everyone else reads from them, so your
changes affect everyone.

## Steps

1. Log in to AWS (any method). For example:

   ```
   export AWS_PROFILE=unimelb-warehouse-prod-poweruser
   aws sso login
   ```

2. Load the shell functions from [dx.sh](../../dx.sh) and connect to the dev warehouse:

   ```
   source dx.sh
   house_up
   ```

3. Switch to the shared schemas. The output should show `ORCAVAULT_SCHEMA=public`, and no
   `DBT_DEFER` or `DBT_STATE`:

   ```
   house_shared
   ```

4. Check the connection, then install the dbt packages. `dbt debug` should print
   `All checks passed!`:

   ```
   dbt debug
   dbt deps
   ```

5. Build only the models you mean to change, not the whole project:

   ```
   dbt build -s sal_library
   dbt build -s sal_library+             # the model and everything downstream
   ```

   Other dbt commands work as usual, for example `dbt compile`, `dbt run`, `dbt test` and
   `dbt seed`. See `dbt --help`.

6. Disconnect when you are done:

   ```
   house_down
   ```

## Full refresh

dbt can build an incremental model in two ways:

- **Normal run:** adds only the rows that are new since the last run, and keeps the rest.
- **`--full-refresh`:** drops the table and rebuilds it from scratch.

Use a full refresh when a logic change must apply to every row, not only new ones. In the
shared schemas this **loses the model's `load_datetime` history**, because every row gets the
time of the refresh run. So refresh only the models you need, by name:

```
dbt run -s sal_library --full-refresh
```

Never run a full refresh on the whole project here. Only the business vault may be refreshed
freely; the raw vault and PSA need a core maintainer's agreement. See
[data-vault.md](../architecture/data-vault.md#rebuilding-layers).

## Switching back to a personal schema

`house_down` does not clear `ORCAVAULT_SCHEMA=public`, and `house_up` keeps whatever value is
already set. To go back to your personal schema in the same shell, unset it first:

```
unset ORCAVAULT_SCHEMA
house_up
```

Opening a new shell also works.

## What is different

|                                      | Personal schema                          | Shared schema                                |
|--------------------------------------|------------------------------------------|----------------------------------------------|
| `ORCAVAULT_SCHEMA`                   | `dev_<sso_username>`                     | `public`                                     |
| Schemas you build into               | `<personal>_psa`, `<personal>_dcl`, ...  | `psa`, `dcl`, `mart`, ...                    |
| `DBT_DEFER` / `DBT_STATE`            | Set, so unchanged models read from dev   | Not set                                      |
| CDC watermarks (`ops.cdc_watermark`) | Read only                                | **Moved by your run**, as the daily run does |

The watermark row matters most. A shared run records how far each CDC source has been
loaded, just like the daily run, so the next daily run carries on from your point.

Where this is decided in the code:

- Schema names: `macros/generate_schema_name.sql`.
- Watermarks: `is_personal_target()` in `macros/ops/`. Design:
  [cdc-watermark.md](../architecture/cdc-watermark.md).
