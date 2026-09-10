-- Run from the database where pg_cron is installed, usually postgres.
-- The commands below execute in the warehouse database as warehouse_etl.
-- Idempotent — unschedules existing jobs by name before recreating them.

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Unschedule first so reruns don't hit unique-name constraint
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'care-fdw-hourly-refresh';
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'care-fdw-daily-refresh';
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'care-fdw-clean-cron-history';

SELECT cron.schedule_in_database(
  'care-fdw-hourly-refresh',
  '7 * * * *',
  $$SELECT etl.refresh_group('hourly');$$,
  :'WAREHOUSE_DB',
  'warehouse_etl'
);

SELECT cron.schedule_in_database(
  'care-fdw-daily-refresh',
  '0 2 * * *',
  $$SELECT etl.refresh_group('daily');$$,
  :'WAREHOUSE_DB',
  'warehouse_etl'
);

SELECT cron.schedule_in_database(
  'care-fdw-clean-cron-history',
  '30 3 1 * *',
  $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '14 days';$$,
  'postgres'
);

-- Inspect schedules.
SELECT jobid, jobname, schedule, database, username, active
FROM cron.job
ORDER BY jobname;

-- Recent runs.
SELECT jobid, status, return_message, start_time, end_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 50;

-- Unschedule examples. Prefer jobid on managed Postgres because pg_cron uses
-- row-level policies around job ownership.
-- SELECT cron.unschedule(jobid)
-- FROM cron.job
-- WHERE jobname = 'care-fdw-hourly-refresh';
--
-- SELECT cron.unschedule(jobid)
-- FROM cron.job
-- WHERE jobname = 'care-fdw-daily-refresh';
