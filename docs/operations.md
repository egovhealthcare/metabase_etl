# Operations Runbook

## Manual Refresh

Refresh one table:

```sql
SELECT etl.refresh_table('facility_facility');
```

Refresh a group:

```sql
SELECT etl.refresh_group('hourly');
SELECT etl.refresh_group('daily');
```

Check status:

```sql
SELECT *
FROM etl.replication_status
ORDER BY refresh_group, priority, table_name;
```

Check recent failures:

```sql
SELECT *
FROM etl.replication_runs
WHERE status = 'failed'
ORDER BY started_at DESC
LIMIT 50;
```

## Initial Load

Run initial loads off-peak. Start with dimensions, then smaller facts, then high
volume facts like `emr_observation`.

```sql
SELECT etl.refresh_group('daily');
SELECT etl.refresh_table('facility_facility');
SELECT etl.refresh_table('emr_patient');
SELECT etl.refresh_table('emr_encounter');
SELECT etl.refresh_table('emr_observation');
```

## Load Control

Keep FDW impact on the read replica controlled:

```sql
ALTER ROLE warehouse_fdw_reader CONNECTION LIMIT 2;
ALTER ROLE warehouse_fdw_reader SET statement_timeout = '5min';
```

Increase each table's lookback if replica lag is higher than expected:

```sql
UPDATE etl.replication_tables
SET lookback = interval '6 hours'
WHERE table_name = 'emr_observation';
```

Disable a noisy table while investigating:

```sql
UPDATE etl.replication_tables
SET enabled = false
WHERE table_name = 'emr_observation';
```

## FDW Role Mapping Issues

FDW connections are resolved per local database role. If an admin user can run
`etl.refresh_*()` but `warehouse_etl` or cron cannot, check the `warehouse_etl`
foreign server grant and user mapping.

Run on the warehouse database:

```sql
GRANT USAGE ON FOREIGN SERVER care_read_replica TO warehouse_etl;
GRANT USAGE ON SCHEMA replica, raw, etl TO warehouse_etl;
GRANT SELECT ON ALL TABLES IN SCHEMA replica TO warehouse_etl;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA raw TO warehouse_etl;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA etl TO warehouse_etl;

DROP USER MAPPING IF EXISTS FOR warehouse_etl SERVER care_read_replica;

CREATE USER MAPPING FOR warehouse_etl
SERVER care_read_replica
OPTIONS (
  user 'warehouse_fdw_reader',
  password 'CHANGE_ME_SOURCE_READER_PASSWORD'
);
```

Test as `warehouse_etl`:

```sql
SET ROLE warehouse_etl;
SELECT id
FROM replica.facility_facility
LIMIT 1;


SELECT etl.refresh_table('facility_facility');

RESET ROLE;
```

## Metabase

Metabase should connect with `metabase_reader` and query only:

```text
raw.*
mart.*
etl.replication_status
```

Do not grant Metabase access to `replica.*`. Those tables are live FDW reads
against the source read replica.

## Schema Drift

The raw table is created from the FDW table on first refresh. If a source model
adds/removes columns later:

1. Pause schedules.
2. Re-import foreign tables with `sql/02-import-care-foreign-tables.sql`.
3. For affected raw tables, either apply compatible `ALTER TABLE raw...` changes
   or recreate the raw table.
4. Run a manual refresh.
5. Resume schedules.

For a full rebuild of one table:

```sql
DROP TABLE IF EXISTS raw.emr_patient;
DELETE FROM etl.replication_state WHERE table_name = 'emr_patient';
SELECT etl.refresh_table('emr_patient');
```

## Clean Rebuild

During initial setup, if several raw tables were created with the wrong owner or
grants, rebuild the raw layer instead of repairing each table one by one.

Run this from the warehouse database after pausing cron jobs:

```sql
DROP SCHEMA IF EXISTS raw CASCADE;
CREATE SCHEMA raw;

GRANT USAGE, CREATE ON SCHEMA raw TO warehouse_etl;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA raw TO warehouse_etl;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA raw TO warehouse_etl;

TRUNCATE etl.replication_state;
TRUNCATE etl.replication_runs RESTART IDENTITY;
```

Then run the setup functions file again and trigger a staged initial sync:

```sql
SELECT etl.refresh_table('facility_facility');
SELECT etl.refresh_group('daily');
SELECT etl.refresh_group('hourly');
```

## Cron Monitoring

Run from the database where `pg_cron` is installed:

```sql
SELECT jobid, jobname, schedule, database, username, active
FROM cron.job
ORDER BY jobname;

SELECT jobid, status, return_message, start_time, end_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 50;
```

## Suggested Mart Pattern

Keep raw tables close to source shape. Put analytics-friendly joins and filters
in `mart.*`.

```sql
CREATE OR REPLACE VIEW mart.active_facilities AS
SELECT
  id,
  external_id,
  name,
  facility_type,
  is_active,
  verified,
  modified_date
FROM raw.facility_facility
WHERE deleted = false;
```
