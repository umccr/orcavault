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
