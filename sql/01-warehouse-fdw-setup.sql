-- Run on the warehouse database as postgres/cloudsqlsuperuser or equivalent.
-- Credentials and connection details are injected via psql -v variables.

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE SCHEMA IF NOT EXISTS replica;
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS etl;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warehouse_etl') THEN
    CREATE ROLE warehouse_etl LOGIN PASSWORD :'WAREHOUSE_ETL_PASSWORD';
  END IF;
END;
$$;

-- Sync password on reruns when role already exists
ALTER ROLE warehouse_etl PASSWORD :'WAREHOUSE_ETL_PASSWORD';

GRANT CONNECT ON DATABASE metabase_warehouse TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA replica TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA raw TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA mart TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA etl TO warehouse_etl;

DROP SERVER IF EXISTS care_read_replica CASCADE;

CREATE SERVER care_read_replica
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (
  host :'SOURCE_REPLICA_HOST',
  port '5432',
  dbname :'SOURCE_DBNAME',
  fetch_size '10000'
);

GRANT USAGE ON FOREIGN SERVER care_read_replica TO warehouse_etl;

DROP USER MAPPING IF EXISTS FOR warehouse_etl SERVER care_read_replica;

CREATE USER MAPPING FOR warehouse_etl
SERVER care_read_replica
OPTIONS (
  user 'warehouse_fdw_reader',
  password :'FDW_READER_PASSWORD'
);

-- Optional, useful while testing as the current admin user.
DROP USER MAPPING IF EXISTS FOR CURRENT_USER SERVER care_read_replica;

CREATE USER MAPPING FOR CURRENT_USER
SERVER care_read_replica
OPTIONS (
  user 'warehouse_fdw_reader',
  password :'FDW_READER_PASSWORD'
);
