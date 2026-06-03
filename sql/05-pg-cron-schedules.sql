-- Run from the database where pg_cron is installed, usually postgres.
-- The commands below execute in the warehouse database as warehouse_etl.
-- Replace warehouse if your warehouse database has a different name.

CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule_in_database(
  'care-fdw-hourly-refresh',
  '7 * * * *',
  $$SELECT etl.refresh_group('hourly');$$,
  'warehouse',
  'warehouse_etl'
);

SELECT cron.schedule_in_database(
  'care-fdw-daily-refresh',
  '0 2 * * *',
  $$SELECT etl.refresh_group('daily');$$,
  'warehouse',
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

-- Unschedule examples.
-- SELECT cron.unschedule('care-fdw-hourly-refresh');
-- SELECT cron.unschedule('care-fdw-daily-refresh');
