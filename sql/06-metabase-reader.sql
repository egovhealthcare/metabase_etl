-- Run on the warehouse database.
-- Replace password before execution.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'metabase_reader') THEN
    CREATE ROLE metabase_reader LOGIN PASSWORD 'CHANGE_ME_METABASE_PASSWORD';
  END IF;
END;
$$;

GRANT CONNECT ON DATABASE warehouse TO metabase_reader;
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

