# Operations Runbook

Use this guide for routine refreshes, monitoring, and load control. For failed
deployments, schema drift, or destructive rebuilds, use the
[recovery runbook](recovery.md).

Run the following commands on `metabase_warehouse` unless a section says
otherwise.

## How Refreshes Work

The registry in `etl.replication_tables` selects one of two modes:

| Mode | Behavior |
|---|---|
| `full` | Truncates the local `raw.*` table and reloads it from `replica.*` |
| `incremental` | Reads rows changed since the last `modified_date` watermark minus the configured lookback, then upserts by `id` |

If an incremental table has no `modified_date` column,
`etl.incremental_refresh_table()` delegates to a full refresh. The lookback
protects against source-replica lag by rereading a bounded period; increase it
when observed lag exceeds the configured interval.

`include_deleted = true` preserves soft-deleted rows in `raw.*`. The current
registry uses this setting so reporting models can decide whether to filter
`deleted = false`.

## Refresh Data

Refresh one table:

```sql
SELECT etl.refresh_table('facility_facility');
```

Refresh scheduled groups:

```sql
SELECT etl.refresh_group('hourly');
SELECT etl.refresh_group('daily');
```

Run initial loads off-peak. Start with daily dimensions, then smaller facts,
then high-volume facts:

```sql
SELECT etl.refresh_group('daily');
SELECT etl.refresh_table('emr_patient');
SELECT etl.refresh_table('emr_encounter');
SELECT etl.refresh_table('emr_observation');
```

## Check Health

Current table status:

```sql
SELECT *
FROM etl.replication_status
ORDER BY refresh_group, priority, table_name;
```

Recent failures:

```sql
SELECT table_name, started_at, finished_at, error_message
FROM etl.replication_runs
WHERE status = 'failed'
ORDER BY started_at DESC
LIMIT 50;
```

Cron schedules and recent runs must be queried from the warehouse `postgres`
database:

```sql
SELECT jobid, jobname, schedule, database, username, active
FROM cron.job
ORDER BY jobname;

SELECT jobid, status, return_message, start_time, end_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 50;
```

Run cron-management commands as the value of
`infra.outputs.metabase_database_user` from `gcp_template`. PR #28 embeds that
user in `POSTGRES_URL`, and `sql/05` uses that connection to schedule jobs that
execute as `warehouse_etl`. Use the same connection because pg_cron restricts
job visibility and modification by role.

## Pause and Resume Schedules

Pause the ETL schedules before changing `replica.*`, rebuilding data, or
applying a Metabase Helm release:

```sql
SELECT current_user;

SELECT jobid, jobname, username, active
FROM cron.job
WHERE jobname IN (
  'care-fdw-hourly-refresh',
  'care-fdw-daily-refresh'
)
ORDER BY jobname;

SELECT to_regprocedure(
  'cron.alter_job(bigint,text,text,text,text,boolean)'
) AS alter_job_function;

SELECT cron.alter_job(jobid, active := false)
FROM cron.job
WHERE jobname IN (
  'care-fdw-hourly-refresh',
  'care-fdw-daily-refresh'
);

SELECT jobname, username, active
FROM cron.job
WHERE jobname IN (
  'care-fdw-hourly-refresh',
  'care-fdw-daily-refresh'
)
ORDER BY jobname;
```

`current_user` must equal `infra.outputs.metabase_database_user`. On an
existing deployment, the inventory query must list both jobs with
`username = 'warehouse_etl'`; an empty result under another login does not
prove that no jobs exist. On a first deployment, neither job exists and there
is nothing to pause.

The function check must return the `cron.alter_job` signature. Stop if it
returns `NULL`; this runbook does not assume an unverified pg_cron function
version. Both existing jobs must then show `active = false`. Resume them after
validation:

```sql
SELECT cron.alter_job(jobid, active := true)
FROM cron.job
WHERE jobname IN (
  'care-fdw-hourly-refresh',
  'care-fdw-daily-refresh'
);

SELECT jobname, username, active
FROM cron.job
WHERE jobname IN (
  'care-fdw-hourly-refresh',
  'care-fdw-daily-refresh'
)
ORDER BY jobname;
```

Both jobs must show `active = true`. The monthly history-cleanup job does not
query warehouse schemas and does not need to be paused for schema maintenance.

## Control Source Load

The source reader is deliberately constrained:

```sql
ALTER ROLE warehouse_fdw_reader CONNECTION LIMIT 2;
ALTER ROLE warehouse_fdw_reader SET statement_timeout = '5min';
```

If replica lag exceeds a table's lookback window:

```sql
UPDATE etl.replication_tables
SET lookback = interval '6 hours'
WHERE table_name = 'emr_observation';
```

Temporarily disable a noisy table:

```sql
UPDATE etl.replication_tables
SET enabled = false
WHERE table_name = 'emr_observation';
```

Re-enable it after investigation:

```sql
UPDATE etl.replication_tables
SET enabled = true
WHERE table_name = 'emr_observation';
```

## Metabase Access

Metabase connects as `metabase_reader` and may query:

```text
raw.*
mart.*
etl.replication_status
```

Never grant Metabase access to `replica.*`; those queries execute against the
source read replica.

## Add Reporting Models

Keep `raw.*` close to the source shape. Put analytics-friendly joins, names,
and filters in `mart.*`:

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

Grant `metabase_reader` access to new mart objects if the applicable default
privileges were not created by `sql/06-metabase-reader.sql`.
