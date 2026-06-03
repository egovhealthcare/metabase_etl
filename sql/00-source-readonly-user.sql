-- Run on the source primary only if this role does not already exist.
-- PostgreSQL roles and grants replicate to Cloud SQL read replicas.
-- Replace care with your source database name if different.

CREATE ROLE warehouse_fdw_reader
  LOGIN
  PASSWORD 'CHANGE_ME_STRONG_PASSWORD'
  CONNECTION LIMIT 2;

GRANT CONNECT ON DATABASE care TO warehouse_fdw_reader;
GRANT USAGE ON SCHEMA public TO warehouse_fdw_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO warehouse_fdw_reader;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO warehouse_fdw_reader;

ALTER ROLE warehouse_fdw_reader SET statement_timeout = '5min';
ALTER ROLE warehouse_fdw_reader SET idle_in_transaction_session_timeout = '1min';

