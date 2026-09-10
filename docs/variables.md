# Deployment Variables

This page maps the actual OpenTofu values from
[`egovhealthcare/gcp_template#28`](https://github.com/egovhealthcare/gcp_template/pull/28)
to the environment consumed by this repository's SQL.

## End-to-End Flow

```text
gcp_template tfvars and remote state
                 |
                 v
OpenTofu kubernetes_secret.metabase_etl
                 |
                 v
Kubernetes Secret: metabase-etl-secret
                 |
              envFrom
                 |
                 v
Helm provision Job -> psql -v NAME="$NAME" -> sql/00 ... sql/06
```

## User-Configured Inputs

Only two ETL-specific values are set in the `gcp_template` environment tfvars:

| OpenTofu variable | Required | Default | Meaning |
|---|---:|---|---|
| `metabase_etl_repo` | To enable ETL | `null` | Public GitHub repository in `owner/repo` format |
| `metabase_etl_branch` | No | `main` | Branch, tag, or commit SHA fetched by the Job |

Recommended production configuration:

```hcl
metabase_etl_repo   = "egovhealthcare/metabase_etl"
metabase_etl_branch = "<reviewed-commit-sha>"
```

Use a commit SHA rather than `main` so review, plan, and execution refer to the
same SQL revision.

## Manual Deployment Values

Cloud SQL Studio does not read `metabase-etl-secret`. For the manual path,
create three independent random passwords and store them outside this
repository in the secret system used by the deployment:

| Value | Used in |
|---|---|
| `FDW_READER_PASSWORD` | `sql/00` and `sql/01`; the value must be identical in both files |
| `WAREHOUSE_ETL_PASSWORD` | `sql/01` |
| `METABASE_READER_PASSWORD` | `sql/06` and the Metabase database connection |

When `warehouse_fdw_reader` already exists and `sql/00` is skipped, use that
role's current password for `FDW_READER_PASSWORD` in `sql/01`. Supplying a new
value only to `sql/01` creates user mappings that cannot authenticate.

Cloud SQL Studio requires manual substitution. Escape each password as a
PostgreSQL string literal; do not paste an unescaped value into the SQL and do
not save substituted SQL files in the repository.

## Generated and Derived Values

OpenTofu builds `metabase-etl-secret` from KMS-stack outputs, infrastructure
remote state, and environment variables:

| Secret key | Source in `gcp_template` | Value |
|---|---|---|
| `WAREHOUSE_URL` | `infra` remote state | Warehouse admin URL for `metabase_warehouse` |
| `POSTGRES_URL` | `infra` remote state | Warehouse admin URL for `postgres` |
| `CARE_SOURCE_URL` | `infra` remote state and `app`/`environment` | CARE primary admin URL for `${app}_${environment}` |
| `WAREHOUSE_DB` | Fixed by deploy module | `metabase_warehouse` |
| `SOURCE_REPLICA_HOST` | `infra.outputs.read_replica_address` | Private IP of the first CARE read replica |
| `SOURCE_DBNAME` | `app` and `environment` | `${app}_${environment}` |
| `WAREHOUSE_ETL_PASSWORD` | `keys.outputs.warehouse_etl_password` | Generated 32-character role password |
| `FDW_READER_PASSWORD` | `keys.outputs.warehouse_fdw_reader_password` | Generated 32-character role password |
| `METABASE_READER_PASSWORD` | `keys.outputs.metabase_reader_password` | Generated 32-character role password |

Provisioning fails its OpenTofu precondition when no read replica exists.
`cloudsql_read_replica_count` must therefore be greater than zero before
enabling `metabase_etl_repo`.

## SQL Variables by File

The Job passes every `-v` value to every file; each file expands only the
variables it references.

| SQL file | Connection | Variables used |
|---|---|---|
| `00-source-readonly-user.sql` | `CARE_SOURCE_URL` | `SOURCE_DBNAME`, `FDW_READER_PASSWORD` |
| `01-warehouse-fdw-setup.sql` | `WAREHOUSE_URL` | `SOURCE_REPLICA_HOST`, `SOURCE_DBNAME`, `FDW_READER_PASSWORD`, `WAREHOUSE_ETL_PASSWORD` |
| `02-import-care-foreign-tables.sql` | `WAREHOUSE_URL` | None |
| `03-etl-functions.sql` | `WAREHOUSE_URL` | None |
| `04-register-care-tables.sql` | `WAREHOUSE_URL` | None |
| `05-pg-cron-schedules.sql` | `POSTGRES_URL` | `WAREHOUSE_DB` |
| `06-metabase-reader.sql` | `WAREHOUSE_URL` | `METABASE_READER_PASSWORD` |

## How `psql` Applies Values

The Job invokes:

```sh
psql "$connstr" \
  -v SOURCE_REPLICA_HOST="$SOURCE_REPLICA_HOST" \
  -v SOURCE_DBNAME="$SOURCE_DBNAME" \
  -v FDW_READER_PASSWORD="$FDW_READER_PASSWORD" \
  -v WAREHOUSE_ETL_PASSWORD="$WAREHOUSE_ETL_PASSWORD" \
  -v WAREHOUSE_DB="$WAREHOUSE_DB" \
  -v METABASE_READER_PASSWORD="$METABASE_READER_PASSWORD" \
  -v ON_ERROR_STOP=1 \
  -f "/sql/$file"
```

The SQL uses two native `psql` forms:

| Form | Behavior | Example |
|---|---|---|
| `:'NAME'` | Escapes the value as an SQL string literal | `host :'SOURCE_REPLICA_HOST'` |
| `:NAME` | Inserts a trusted SQL identifier | `DATABASE :SOURCE_DBNAME` |

For example, when `SOURCE_DBNAME=care_staging`:

```sql
GRANT CONNECT ON DATABASE :SOURCE_DBNAME TO warehouse_fdw_reader;
```

is sent to PostgreSQL as:

```sql
GRANT CONNECT ON DATABASE care_staging TO warehouse_fdw_reader;
```

`SOURCE_DBNAME` is derived from controlled OpenTofu values, not user-provided
SQL text. OpenTofu and Helm do not use `templatefile()`, `envsubst`, or string
replacement on the SQL files.

## Secret Storage

The three role passwords are generated by `random_password` in the `KMS`
stack. Despite that stack's name, the values are OpenTofu-managed secrets and
are present in:

- the `keys` GCS state;
- the `deploy` GCS state through remote-state values and the Kubernetes Secret;
- the `metabase-etl-secret` object in GKE;
- the provision Job's environment while it runs.

Connection URLs also contain existing Cloud SQL administrator credentials and
are present in the `deploy` state and Kubernetes Secret.

`sensitive = true` masks CLI output only. Protect the state backends and
Kubernetes Secret with least-privilege access, encryption, versioning, locking,
and audit logging. Never print the Secret, Job environment, connection URLs,
or complete `psql` command in CI logs.
