# CARE Reporting Warehouse

Postgres-native replication for Metabase:

```text
CARE Cloud SQL read replica
  -> postgres_fdw
  -> replica.* foreign tables
  -> raw.* local snapshots
  -> mart.* reporting models
  -> Metabase
```

The warehouse uses PostgreSQL SQL only. It does not require dbt, Airflow, or
application code.

## Start Here

| Goal | Guide |
|---|---|
| Browse all documentation | [Documentation index](docs/README.md) |
| Configure the OpenTofu integration | [OpenTofu deployment](docs/opentofu-deployment.md) |
| Understand deployment inputs | [Variable reference](docs/variables.md) |
| Deploy manually in Cloud SQL Studio | [Cloud SQL Studio setup](docs/cloud-sql-studio-setup.md) |
| Operate the warehouse | [Operations runbook](docs/operations.md) |
| Recover from failures or schema drift | [Recovery runbook](docs/recovery.md) |
| Review replicated tables | [Table catalog](docs/table-catalog.md) |

The OpenTofu integration is being added in
[`egovhealthcare/gcp_template#28`](https://github.com/egovhealthcare/gcp_template/pull/28).
Cloud SQL Studio remains the manual path until that change is merged and
deployed.

## Repository Layout

```text
sql/00-source-readonly-user.sql      Source read-only FDW role
sql/01-warehouse-fdw-setup.sql       Warehouse schemas, roles, and FDW server
sql/02-import-care-foreign-tables.sql
sql/03-etl-functions.sql             Refresh functions and state
sql/04-register-care-tables.sql      CARE table registry
sql/05-pg-cron-schedules.sql         Refresh schedules
sql/06-metabase-reader.sql           Read-only Metabase role
docs/                                Deployment, operations, and catalog guides
```

The numbered SQL files are the source of truth and must run in order. The
OpenTofu-managed Helm Job clones this repository and passes Kubernetes Secret
values to the existing `psql` variables. It does not render or rewrite SQL.

## Safety Boundary

The warehouse has four schemas:

| Schema | Purpose | Metabase access |
|---|---|---|
| `replica` | Live foreign tables backed by the source read replica | Never |
| `raw` | Local snapshot tables | Read |
| `mart` | Reporting views and materialized views | Read |
| `etl` | Registry, state, logs, and refresh functions | Status view only |

Do not grant Metabase access to `replica.*`. Queries against that schema run on
the source read replica.
