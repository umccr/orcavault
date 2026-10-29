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

Each developer is encouraged to build OrcaVault in their own personal schemas, so nobody overwrites the shared dev
tables or another dev's work. The shared schemas are built by the daily run in
[orcahouse/infra/orcavault-run](https://github.com/umccr/orcahouse/tree/main/infra/orcavault-run). The workflow
to use a personal schema is:

| Command       | Description                                                                                                                                                                           |
|---------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `house_up`    | Connect to the dev warehouse and set the name of the personal schema. This defaults to `dev_firstname_lastname` from the AWS SSO user.                                                |
| `dbt_defer`   | Download the dev daily run manifest, then build any changes for the current personal schema. This is like a diff over dev of your local.                                              |
| `dbt_clone`   | Download the dev daily run manifest, then make a view of the dev tables in your personal schema for unchanged models. This is like a live view of dev plus the changes of your local. |
| `dbt_status`  | Lists what has changed compared to dev.                                                                                                                                               |
| `house_down`  | Close the tunnel and clear the credentials.                                                                                                                                           |

The `dx.sh` script sets `ORCAVAULT_SCHEMA` inside `house_cred`, which is a schema derived from the AWS SSO username. Then
when calling `dbt_defer` or `dbt_clone`, the schema is updated or created on Redshift. By default, all `dbt` commands
have `DBT_DEFER=true` set which allows the personal schema to function, as it instructs dbt to look at the personal schema 
if the model is there and fall back to the dev schema for anything that isn't present. The dev state is
downloaded locally from an S3 bucket which the daily run schedule uploads. When developing, either `dbt_defer`
or `dbt_clone` should be run first to download the state that dbt needs, and to keep it up to date. The state changes
once a day, so this should be done regularly, `dbt_status` will tell you if it's out of sync with dev.

The difference between `dbt_defer` and `dbt_clone` is the following:

- **`dbt_defer`** will effectively compute the difference between your local changes and dev, and place that difference
  into your personal schema. It does this by reading every model you haven't changed from dev directly and 
  building the changes into your personal schema. On Redshift, you would see only the tables that have changed in your
  schema, plus everything downstream, and anything else will be fetched from dev.
- **`dbt_clone`** will create a live view of all unchanged models from dev inside your personal schema, and then place your changes
  on top of that. This won't actually clone any data, it will just link the views. On Redshift, you would see all of the
  dev tables plus any of your changes.

Both of these will sync the manifest from the S3 bucket so that your clone or deferral doesn't drift from what's 
available on dev. They also both use `--full-refresh` as it's what allows
a change to apply to all rows when compared to the dev copy, which is likely the desired workflow for testing out a change.

These commands should be considered "sync" style commands with the dev state. A typical workflow might look like the
following:

* Start with a sync, i.e. run `dbt_defer` or `dbt_clone` once a day to keep your personal schema up to date with dev.
* While working on a model or making a change, execute normal `dbt` commands:
    * For example, if you've edited [`sat_sequencing_run_state.sql`](models/dcl/raw_vault/sequencing/sat_sequencing_run_state.sql), you might run
      `dbt build -s sat_sequencing_run_state+ -f` to apply the changes.
    * Generally you will want to use `--full-refresh` for personal schemas so that all rows are updated with local
      changes, because otherwise not much will have changed in comparison to dev which is running on a regular schedule. 
* If you want to rebuild all changes at once, run `dbt_defer` or `dbt_clone` again. 

These two commands don't necessarily conflict with each other and can be used interchangeably depending on the desired
output. If you run `dbt_defer` after a `dbt_clone` the views won't be deleted, but if you run `dbt_clone` after `dbt_defer`
unchanged tables will be replaced with views.

If you'd like to opt out of this personal schema workflow and use the shared dev schema anyway, run `house_shared` after
running `house_up`.

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
