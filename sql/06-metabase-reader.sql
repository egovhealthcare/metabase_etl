-- Run on the warehouse database.
-- Credentials are injected via psql -v variables.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'metabase_reader') THEN
    CREATE ROLE metabase_reader LOGIN;
  END IF;
END;
$$;

-- Sync password on reruns when role already exists
ALTER ROLE metabase_reader PASSWORD :'METABASE_READER_PASSWORD';

GRANT CONNECT ON DATABASE metabase_warehouse TO metabase_reader;
GRANT USAGE ON SCHEMA raw TO metabase_reader;
GRANT USAGE ON SCHEMA mart TO metabase_reader;
GRANT USAGE ON SCHEMA etl TO metabase_reader;

-- Grant per-table, switching to each table's owner to avoid permission errors.
-- raw.* may be owned by different roles (warehouse_etl via pg_cron, admin via
-- manual ETL calls). Each table can only be granted by its own owner.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT tablename, tableowner
    FROM pg_tables
    WHERE schemaname = 'raw'
  LOOP
    EXECUTE format('SET ROLE %I', r.tableowner);
    EXECUTE format('GRANT SELECT ON TABLE raw.%I TO metabase_reader', r.tablename);
    EXECUTE 'RESET ROLE';
  END LOOP;
END;
$$;

-- Future tables created by warehouse_etl (pg_cron) or admin get SELECT auto-granted.
ALTER DEFAULT PRIVILEGES FOR ROLE warehouse_etl IN SCHEMA raw
  GRANT SELECT ON TABLES TO metabase_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw
  GRANT SELECT ON TABLES TO metabase_reader;

GRANT SELECT ON ALL TABLES IN SCHEMA mart TO metabase_reader;
GRANT SELECT ON etl.replication_status TO metabase_reader;

ALTER DEFAULT PRIVILEGES IN SCHEMA mart
  GRANT SELECT ON TABLES TO metabase_reader;

-- Intentionally no grant on replica.*. Dashboard queries should not hit the
-- source read replica through FDW.

