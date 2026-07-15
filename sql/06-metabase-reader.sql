-- Run on the warehouse database.
-- Credentials are injected via psql -v variables.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'metabase_reader') THEN
    CREATE ROLE metabase_reader LOGIN PASSWORD :'METABASE_READER_PASSWORD';
  END IF;
END;
$$;

-- Sync password on reruns when role already exists
ALTER ROLE metabase_reader PASSWORD :'METABASE_READER_PASSWORD';

GRANT CONNECT ON DATABASE metabase_warehouse TO metabase_reader;
GRANT USAGE ON SCHEMA raw TO metabase_reader;
GRANT USAGE ON SCHEMA mart TO metabase_reader;
GRANT USAGE ON SCHEMA etl TO metabase_reader;

GRANT SELECT ON ALL TABLES IN SCHEMA raw TO metabase_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA mart TO metabase_reader;
GRANT SELECT ON etl.replication_status TO metabase_reader;

ALTER DEFAULT PRIVILEGES IN SCHEMA raw
GRANT SELECT ON TABLES TO metabase_reader;

ALTER DEFAULT PRIVILEGES IN SCHEMA mart
GRANT SELECT ON TABLES TO metabase_reader;

-- Intentionally no grant on replica.*. Dashboard queries should not hit the
-- source read replica through FDW.

