-- Run on the warehouse database as postgres/cloudsqlsuperuser or equivalent.
-- Replace host, dbname, passwords, and role names before execution.

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE SCHEMA IF NOT EXISTS replica;
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS etl;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warehouse_etl') THEN
    CREATE ROLE warehouse_etl LOGIN PASSWORD 'CHANGE_ME_WAREHOUSE_ETL_PASSWORD';
  END IF;
END;
$$;

GRANT CONNECT ON DATABASE warehouse TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA replica TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA raw TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA mart TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA etl TO warehouse_etl;

DROP SERVER IF EXISTS care_read_replica CASCADE;

CREATE SERVER care_read_replica
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (
  host 'READ_REPLICA_PRIVATE_IP_OR_DNS',
  port '5432',
  dbname 'care',
  fetch_size '10000'
);

GRANT USAGE ON FOREIGN SERVER care_read_replica TO warehouse_etl;

CREATE USER MAPPING FOR warehouse_etl
SERVER care_read_replica
OPTIONS (
  user 'warehouse_fdw_reader',
  password 'CHANGE_ME_SOURCE_READER_PASSWORD'
);

-- Optional, useful while testing as the current admin user.
CREATE USER MAPPING IF NOT EXISTS FOR CURRENT_USER
SERVER care_read_replica
OPTIONS (
  user 'warehouse_fdw_reader',
  password 'CHANGE_ME_SOURCE_READER_PASSWORD'
);

