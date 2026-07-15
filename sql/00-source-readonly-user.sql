-- Runs on the CARE source primary DB (not the warehouse).
-- Creates the read-only FDW reader role used by postgres_fdw on the warehouse.
-- Idempotent — safe to re-run; ALTER ROLE syncs the password on reruns.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warehouse_fdw_reader') THEN
    CREATE ROLE warehouse_fdw_reader
      LOGIN PASSWORD :'FDW_READER_PASSWORD'
      CONNECTION LIMIT 2;
  END IF;
END;
$$;

ALTER ROLE warehouse_fdw_reader PASSWORD :'FDW_READER_PASSWORD';

GRANT CONNECT ON DATABASE :SOURCE_DBNAME TO warehouse_fdw_reader;
GRANT USAGE ON SCHEMA public TO warehouse_fdw_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO warehouse_fdw_reader;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO warehouse_fdw_reader;

ALTER ROLE warehouse_fdw_reader SET statement_timeout = '5min';
ALTER ROLE warehouse_fdw_reader SET idle_in_transaction_session_timeout = '1min';

