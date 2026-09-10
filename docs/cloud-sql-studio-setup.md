# Manual Deployment with Cloud SQL Studio

Use this runbook for the current manual deployment path. The
[OpenTofu deployment guide](opentofu-deployment.md) describes the automated
path being added in `egovhealthcare/gcp_template`.

The SQL files are the source of truth. This guide deliberately does not copy
their contents, so deployment instructions cannot drift from the reviewed SQL.

## Prerequisites

- A CARE source primary and read replica.
- A separate warehouse Cloud SQL for PostgreSQL instance.
- Private network connectivity from the warehouse to the source read replica.
- An administrator account on the source primary and warehouse.
- A warehouse database named `metabase_warehouse`.
- `cloudsql.enable_pg_cron=on` on the warehouse instance. Changing this flag
  restarts the instance.
- Values from the [variable reference](variables.md).

Cloud SQL Studio does not expand `psql` variables. Before running a
parameterized file, replace each `:'VARIABLE'` with a quoted SQL literal and
each `:VARIABLE` with a valid SQL identifier. Never commit the resulting file.

## Run the Scripts

| Order | File | Instance | Database | Notes |
|---:|---|---|---|---|
| 00 | `sql/00-source-readonly-user.sql` | Source primary | Source database | Required unless the existing FDW role password is reused by `sql/01` |
| 01 | `sql/01-warehouse-fdw-setup.sql` | Warehouse | `metabase_warehouse` | Points FDW at the read replica, never the primary |
| 02 | `sql/02-import-care-foreign-tables.sql` | Warehouse | `metabase_warehouse` | Recreates `replica.*` |
| 03 | `sql/03-etl-functions.sql` | Warehouse | `metabase_warehouse` | Creates ETL state and functions |
| 04 | `sql/04-register-care-tables.sql` | Warehouse | `metabase_warehouse` | Registers refresh modes and schedules |
| 05 | `sql/05-pg-cron-schedules.sql` | Warehouse | `postgres` | Run where `pg_cron` is installed |
| 06 | `sql/06-metabase-reader.sql` | Warehouse | `metabase_warehouse` | Grants no access to `replica.*` |

For each row:

1. Open Cloud SQL Studio on the listed instance and database.
2. Open the matching repository file.
3. Substitute only the variables documented for that file.
4. Run the complete file.
5. Stop on any error before continuing to the next file.

`sql/01-warehouse-fdw-setup.sql` drops and recreates the foreign server. Always
run `sql/02-import-care-foreign-tables.sql` after it.

## Verify the Deployment

On `metabase_warehouse`:

```sql
SELECT srvname FROM pg_foreign_server;

SELECT count(*) FROM replica.facility_facility;

SELECT etl.refresh_table('facility_facility');

SELECT count(*) FROM raw.facility_facility;

SELECT *
FROM etl.replication_status
ORDER BY refresh_group, priority, table_name;
```

On the warehouse `postgres` database:

```sql
SELECT jobname, schedule, database, username, active
FROM cron.job
ORDER BY jobname;
```

Connect Metabase with `metabase_reader` and expose only `raw`, `mart`, and
`etl.replication_status`.

## Common Failures

| Error | Check |
|---|---|
| `could not connect to server` | Private IP, VPC routing, and the read-replica host |
| `permission denied for relation` | Source grants and the `warehouse_etl` user mapping |
| `relation "replica..." does not exist` | Source schema drift and the import list in `sql/02` |
| `pg_cron extension not available` | Cloud SQL flag and instance restart |
| Incremental rows are missing | Increase the table lookback beyond replica lag |

See the [operations runbook](operations.md) for monitoring and the
[recovery runbook](recovery.md) for failures or teardown.
