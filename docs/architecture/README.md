# Architecture overview

OrcaVault is the UMCCR **data warehouse** build: a dbt project that loads upstream sources
(OrcaBus services via CDC, spreadsheets, legacy sources) into Amazon Redshift and models them
into a Data Vault and consumer-facing marts.

Project docs: https://github.com/umccr/orcahouse-doc
Issues: https://github.com/umccr/orcahouse-project/issues

## Scope

- OrcaVault owns data production for the warehouse. Downstream consumers read the marts, so
  mart columns are a contract.
- The vault keeps history. Correctness and auditability (load history, deletes,
  effectivity) come before convenience.
- The shared dev schemas are built by the daily run in
  [umccr/orcahouse `infra/orcavault-run`](https://github.com/umccr/orcahouse/tree/main/infra/orcavault-run).
  Developers build into personal schemas ([personal-schemas.md](../dev/personal-schemas.md)).

## Platform

- A dbt project with the `dbt-redshift` adapter, on Amazon Redshift Serverless. Development
  is remote: dbt runs locally and builds in the dev Redshift workgroup. There is no local database.
- Redshift sits in a private subnet and is never exposed to the internet.
- Developers reach it through an SSH tunnel to `127.0.0.1:5439`, via a management instance
  opened with EC2 Instance Connect. No VPN is involved. `house_up` sets it up
  ([personal-schemas.md](../dev/personal-schemas.md)).
- The infrastructure (Redshift, the management instance, networking and the daily run) is
  managed with Terraform in [umccr/orcahouse](https://github.com/umccr/orcahouse).

## Layers

Each folder under `models/` builds into its own schema (`dbt_project.yml`). Schema names come
from `macros/generate_schema_name.sql`: shared targets use the layer schema, personal targets
prefix it with the personal schema name.

| Folder                    | Contents                                                     |
|---------------------------|--------------------------------------------------------------|
| `tsa/`, `legacy/`, `cdc/` | Source declarations (`_sources.yml`) and `int_cdc_*` staging |
| `psa/`                    | Persistent staging (e.g. `spreadsheet__*`)                   |
| `dcl/raw_vault/`          | `hub_`, `link_`, `sat_` per business entity sub-folder       |
| `dcl/business_vault/`     | `effsat_`, `sal_` and derived satellites                     |
| `mart/`                   | Consumer marts in `centre/` and `external/` (`lims`, `em_*`, ...) |

Seeds build into the `seed` schema (`seeds/accreditation`, `seeds/dictionary`, `seeds/mdm`). Data tests are in
`tests/` (`assert_*.sql`), with fixtures under `tests/fixtures/`.

## Design topics

- [data-vault.md](data-vault.md): Data Vault production rules, e.g. which layers may be fully refreshed
- [cdc-watermark.md](cdc-watermark.md): incremental loading with CDC watermarks
- [cdc-deletes.md](cdc-deletes.md): how deletes flow through the vault
