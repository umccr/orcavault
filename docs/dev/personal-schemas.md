# Personal schemas

Build OrcaVault in your own personal schema. This way you never overwrite the shared dev
tables or another developer's work.

## Steps

1. Install the dev toolchain into a Python virtual environment (any tool works). The
   packages are listed in [requirements.txt](../../requirements.txt).

   ```
   python3 -m venv .venv
   source .venv/bin/activate
   make install
   make check
   ```

2. Log in to AWS (any method). For example:

   ```
   export AWS_PROFILE=unimelb-warehouse-prod-poweruser
   aws sso login
   ```

3. Load the shell functions from [dx.sh](../../dx.sh):

   ```
   source dx.sh
   ```

4. Connect to the dev warehouse. This also sets your personal schema name:

   ```
   house_up
   house_schema          # prints your schema name
   ```

5. Check the connection. `dbt debug` should print `All checks passed!`. Then install the dbt
   packages listed in [packages.yml](../../packages.yml). Other dbt commands fail with a
   compilation error until you do. Run `dbt deps` once per clone, and again after `dbt clean`,
   which removes the packages:

   ```
   dbt debug
   dbt deps
   ```

6. Sync your schema with the dev daily run. Do this once a day, or when `house_up` tells you
   dev has run since your last sync:

   ```
   dbt_defer             # or dbt_clone, see "Defer or clone?" below
   ```

7. Build your change and everything downstream of it:

   ```
   dbt build -s <model>+ -f          # -f is short for --full-refresh
   ```

   `-f` is fine here, but not in shared schemas; see
   [`-f` is for your schema only](#-f-is-for-your-schema-only).

8. See what differs from dev:

   ```
   dbt_status
   ```

9. Disconnect when you are done:

   ```
   house_down
   ```

## Reconnecting

If dbt cannot connect, the tunnel has usually dropped, for example after sleep, a network
change or a network drop. You do not need `house_up` again. The key, the hosts entry and the dbt
credentials are still in place, so only restart the tunnel.

1. If your AWS session has expired, log in again:

   ```
   aws sso login
   ```

2. Check whether the tunnel is still running. No output means it is gone:

   ```
   house_status
   ```

3. If a stale tunnel is still listed but not working, stop it:

   ```
   house_stop
   ```

4. Start the tunnel again and check the port is open:

   ```
   house_tunnel
   house_nc
   ```

This only works in the same shell. In a new shell the dbt credentials are gone, so run
`source dx.sh` and `house_up` instead.

## How `dbt_defer` works

`dbt_defer` in [dx.sh](../../dx.sh) is a single line. The helper functions it calls do the
work.

1. `dbt_defer`

   ```bash
   house_fetch && dbt_rebuild "$@"
   ```

   Downloads the dev manifest, then rebuilds. The rebuild only runs if the download succeeds
   (`&&`). `"$@"` passes any extra arguments on to `dbt build`, for example
   `dbt_defer --exclude <model>`.

2. `house_fetch`

   ```bash
   aws s3 cp "$(house_upstream)" "${1:-target/upstream/manifest.json}"
   ```

   Downloads the manifest of what the dev daily run built. It saves to
   `target/upstream/manifest.json` by default. `house_check_sync` saves to
   `target/upstream/latest.json` instead, so it can compare the two without overwriting.

3. `house_upstream`

   ```bash
   echo "s3://orcavault-run-dev-results-<account>-ap-southeast-2-an/state/manifest.json"
   ```

   Returns the S3 path of the manifest. It looks up the AWS account ID with
   `aws sts get-caller-identity`, so it needs a logged-in AWS session.

4. `dbt_rebuild`

   ```bash
   dbt build --select state:modified+ --defer --favor-state --state target/upstream --full-refresh "$@"
   ```

   | Part                      | What it does                                                                         |
   |---------------------------|--------------------------------------------------------------------------------------|
   | `build`                   | Runs seeds, models, snapshots and tests in dependency order.                         |
   | `--state target/upstream` | Compares your project with the dev manifest just downloaded.                         |
   | `--select state:modified` | Picks what differs from dev: changed SQL, config or seed data, and anything new.     |
   | `+` (suffix)              | Also picks everything downstream of those.                                           |
   | `--defer`                 | Lets a `ref()` to anything not picked read from dev instead of your schema.          |
   | `--favor-state`           | Always reads from dev, even if an older copy exists in your schema.                  |
   | `--full-refresh`          | Rebuilds incremental models from scratch, so a logic change applies to every row.    |

`house_cred` (run by `house_up`) already exports `DBT_DEFER=true` and
`DBT_STATE=target/upstream`. So a plain `dbt run` or `dbt build` also reads from dev.
`dbt_rebuild` spells the flags out and adds `--favor-state`.

## How `dbt_clone` works

`dbt_clone` in [dx.sh](../../dx.sh) runs three steps. Each step only runs if the one before it
succeeds:

```bash
house_fetch \
  && dbt clone --exclude state:modified+ --state target/upstream --full-refresh \
  && dbt_rebuild "$@"
```

1. `house_fetch`

   Same as in `dbt_defer`: downloads the dev manifest to `target/upstream/manifest.json`.

2. `dbt clone --exclude state:modified+ --state target/upstream --full-refresh`

   | Part                        | What it does                                                                     |
   |-----------------------------|----------------------------------------------------------------------------------|
   | `dbt clone`                 | Creates an object in your schema for each picked model, pointing at its dev copy. |
   | `--state target/upstream`   | Tells dbt where each dev copy lives, using the dev manifest.                     |
   | `--exclude state:modified+` | Picks everything except your changes and their downstream. Step 3 builds those.  |
   | `--full-refresh`            | Recreates each clone even if it already exists. Otherwise existing ones are skipped. |

   Redshift cannot clone tables without copying data, so dbt creates a view instead
   (`select * from <dev table>`). No data is copied, and the view always shows current dev
   data.

3. `dbt_rebuild "$@"`

   Same as in `dbt_defer`. Your changes and their downstream are built as real tables,
   replacing any views from step 2.

## Workflow

The shared dev schemas are built by the daily run in
[orcahouse/infra/orcavault-run](https://github.com/umccr/orcahouse/tree/main/infra/orcavault-run).
Your personal schema sits on top of them, like a diff: it holds your changes, and reads
everything else from dev.

### Commands

| Command      | What it does                                                                                   |
|--------------|------------------------------------------------------------------------------------------------|
| `house_up`   | Connects to the dev warehouse and sets your schema name (default `dev_firstname_lastname`).    |
| `dbt_defer`  | Downloads the dev manifest, then builds only your changes into your schema.                    |
| `dbt_clone`  | Same as `dbt_defer`, but first adds a view of every unchanged dev table to your schema.        |
| `dbt_status` | Lists what differs from dev, and warns if you are out of sync.                                 |
| `house_down` | Closes the tunnel and clears the credentials.                                                  |

`house_up` runs these steps, which are also separate functions: `house_key`, `house_host`,
`house_tunnel`, `house_nc` and `house_cred`.

### Schema name

Your schema is named after your AWS SSO username, for example `dev_firstname_lastname`.
`house_cred` sets it in `ORCAVAULT_SCHEMA`. To use another name, set `ORCAVAULT_SCHEMA` before
`house_up`. The schema is created on Redshift the first time you run `dbt_defer` or
`dbt_clone`.

### Staying in sync

The daily run uploads its manifest to S3 once a day. `dbt_defer` and `dbt_clone` download it,
so dbt knows what dev looks like. Run one of them at the start of each day. `dbt_status` and
`house_up` tell you when you are out of sync.

### Defer or clone?

Both download the dev manifest and build your changes with `--full-refresh`. They differ in
what else ends up in your schema:

|                          | `dbt_defer`                             | `dbt_clone`                                  |
|--------------------------|-----------------------------------------|----------------------------------------------|
| Your changes, downstream | Built as tables                         | Built as tables                              |
| Unchanged models         | Not in your schema; read from dev       | Views of the dev tables (no data copied)     |
| In Redshift you see      | Only your changes and their downstream  | The whole project: dev plus your changes     |

You can switch between them at any time:

- `dbt_defer` after `dbt_clone`: the views stay.
- `dbt_clone` after `dbt_defer`: unchanged tables are replaced with views.

### A typical day

1. Sync once with `dbt_defer` or `dbt_clone`.
2. Edit a model and build it with its downstream. For example, after editing
   [`sat_sequencing_run_state.sql`](../../models/dcl/raw_vault/sequencing/sat_sequencing_run_state.sql):

   ```
   dbt build -s sat_sequencing_run_state+ -f
   ```

   Use `-f` (`--full-refresh`) so every row picks up your change. Without it, an incremental
   model only loads new rows, so little would differ from dev.
3. To rebuild all your changes at once, run `dbt_defer` or `dbt_clone` again.

### `-f` is for your schema only

In your personal schema, `-f` is a convenience: your schema holds no history, so rebuilding it
costs nothing. In the [shared](shared-schemas.md) and production schemas, a full refresh is break-glass only. It
wipes `load_datetime` history that cannot be rebuilt, and the raw vault and PSA need a core
maintainer's agreement first ([data-vault.md](../architecture/data-vault.md#rebuilding-layers)).

So do not let `-f` hide a design problem. Before you raise a PR, ask: would this change work on
the existing shared tables with a normal incremental run? If it only works after a full
refresh, treat that as a design warning. Look for a design that applies going forward, or that
repairs by re-reading (CDC watermark, `reread_from`). If none works, talk to a maintainer before
going further.
