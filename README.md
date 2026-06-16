# Postgres FDW Replication Setup

This directory documents a Postgres-native reporting warehouse pattern:

```text
source Cloud SQL read replica -> postgres_fdw -> warehouse Postgres raw tables -> Metabase
```

The goal is to keep the operating surface to Postgres SQL and Metabase. BigQuery,
Looker Studio, dbt, Airflow, and application code are not required for the base
pipeline.

## Repository Layout

```text
sql/00-source-readonly-user.sql      Optional source role setup
sql/01-warehouse-fdw-setup.sql       Warehouse schemas, roles, FDW server
sql/02-import-care-foreign-tables.sql
sql/03-etl-functions.sql             Generic refresh functions
sql/04-register-care-tables.sql      CARE table registry
sql/05-pg-cron-schedules.sql         Scheduling examples
sql/06-metabase-reader.sql           Read-only Metabase role
docs/table-catalog.md                Tables included from model files
docs/operations.md                   Runbook and troubleshooting
```

## Execution Order

1. Run `sql/00-source-readonly-user.sql` only if the source read-only role does
   not already exist. On Cloud SQL, run this on the source primary once; the role
   and grants replicate to the read replica.
2. Run `sql/01-warehouse-fdw-setup.sql` on the warehouse database as a user that
   can create extensions and foreign servers.
3. Run `sql/02-import-care-foreign-tables.sql` on the warehouse database.
4. Run `sql/03-etl-functions.sql` on the warehouse database.
5. Run `sql/04-register-care-tables.sql` on the warehouse database.
6. Run manual refreshes from the warehouse database.
7. Enable `pg_cron` on the warehouse instance, then run
   `sql/05-pg-cron-schedules.sql` from the database where `pg_cron` is installed,
   usually `postgres`.
8. Run `sql/06-metabase-reader.sql` on the warehouse database, then connect
   Metabase with that role.

## Cloud SQL Notes

Enable `pg_cron` on the warehouse Cloud SQL instance before creating schedules:

Navigate to the GCP Cloud SQL Console, Edit your CloudSQL Instance and Add a new flag

`cloudsql.enable_pg_cron=on`

---

`postgres_fdw` is installed with SQL and does not require the `pg_cron` flag:

```sql
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
```

For Cloud SQL private IP, the warehouse instance and the source read replica
must be reachable over the same VPC/private networking path. The FDW server must
point to the read replica host or private IP, not the primary.

## Schema Contract

The warehouse uses three main schemas:

```text
replica  Foreign tables that point to the read replica.
raw      Local copied tables. Metabase should read these.
mart     Reporting views/materialized views for Metabase.
etl      Refresh registry, state, logs, and functions.
```

Do not expose `replica.*` to dashboard users. `replica.*` is live remote access
to the read replica. Metabase should use `raw.*` and `mart.*`.

## First Smoke Test

After importing foreign tables:

```sql
SELECT id, external_id, name, modified_date
FROM replica.facility_facility
LIMIT 10;
```

Then create and load the local raw copy:

```sql
SELECT etl.refresh_table('facility_facility');

SELECT id, external_id, name, modified_date
FROM raw.facility_facility
LIMIT 10;
```

## Refresh Strategy

The table registry uses two modes:

```text
full         Truncate and reload. Good for small dimension/config tables.
incremental Upsert rows changed since modified_date watermark minus lookback.
```

Most CARE models inherit `modified_date`, so incremental refresh can use a
watermark safely. Keep the lookback window larger than expected replica lag.

For analytics, prefer keeping soft-deleted rows in `raw.*` and filtering
`deleted = false` in `mart.*` views. This preserves delete events and auditability.
