# Project Guidelines

## Overview

Postgres-native reporting warehouse using Foreign Data Wrapper (FDW) to replicate ~75 tables from a Django-based CARE EMR system into a local warehouse for Metabase dashboards. No external orchestrators (dbt, Airflow)—everything is pure PostgreSQL SQL.

See [docs/operations.md](docs/operations.md) for runbooks and [docs/table-catalog.md](docs/table-catalog.md) for the full table registry.

## Architecture

```
Source Cloud SQL read replica (CARE DB)
    ↓ postgres_fdw (read-only)
Warehouse Postgres (4 schemas)
    ├─ replica.*  (live foreign tables — never expose to Metabase)
    ├─ raw.*      (local snapshot copies)
    ├─ mart.*     (reporting views)
    └─ etl.*      (registry, state, functions)
    ↓
Metabase (queries raw.* and mart.* only)
```

## SQL Conventions

| Aspect | Pattern | Example |
|--------|---------|---------|
| Schemas | `replica`, `raw`, `mart`, `etl` | — |
| Table names | `{domain}_{model}` | `facility_facility`, `emr_observation` |
| Function names | `etl.{verb}_{noun}()` | `etl.refresh_table()`, `etl.full_refresh_table()` |
| Role names | `{purpose}_{access}` | `warehouse_fdw_reader`, `warehouse_etl`, `metabase_reader` |
| Registry table | `etl.replication_tables` | Tracks mode, group, priority, lookback, enabled |

## File Execution Order

SQL files are numbered and **must run in sequence**. File `00` runs on the source DB; files `01`–`06` run on the warehouse.

| File | Target DB | Purpose |
|------|-----------|---------|
| `00-source-readonly-user.sql` | Source primary | Create FDW reader role |
| `01-warehouse-fdw-setup.sql` | Warehouse | Schemas, FDW extension, foreign server |
| `02-import-care-foreign-tables.sql` | Warehouse | IMPORT FOREIGN SCHEMA → `replica.*` |
| `03-etl-functions.sql` | Warehouse | ETL functions + state/run tables |
| `04-register-care-tables.sql` | Warehouse | Populate `etl.replication_tables` |
| `05-pg-cron-schedules.sql` | Warehouse (pg_cron) | Cron schedules |
| `06-metabase-reader.sql` | Warehouse | Read-only Metabase role |

## Key Patterns

- **Two refresh modes**: `full` (truncate + reload) for dimensions, `incremental` (upsert by `modified_date` watermark) for facts.
- **Lookback window**: Incremental refresh subtracts a configurable lookback (default 2 hrs) from the watermark to cover replica lag.
- **State tracking**: `etl.replication_state` (watermarks), `etl.replication_runs` (audit log).
- **Scheduling**: `pg_cron` runs `etl.refresh_group('hourly')` at `:07` and `etl.refresh_group('daily')` at `02:00 UTC`.

## Critical Pitfalls

- **Never grant Metabase access to `replica.*`** — queries hit the source read replica directly and can overload it.
- **Incremental refresh assumes `modified_date` column** exists on the source table; tables without it must use `full` mode.
- **FDW grants are per-role** — `warehouse_etl` needs its own USER MAPPING and grants; admin-working doesn't mean cron-working.
- **`pg_cron` requires Cloud SQL flag** `cloudsql.enable_pg_cron=on` before running `05-pg-cron-schedules.sql`.
- **Connection limits**: Keep `warehouse_fdw_reader` at `CONNECTION LIMIT 2` and `statement_timeout = '5min'` to protect the source.

## Adding a New Table

1. Ensure it exists in `replica.*` (re-run `02` if schema drifted).
2. Add a row to `etl.replication_tables` in `sql/04-register-care-tables.sql`.
3. Run `SELECT etl.refresh_table('<table_name>');` to verify.
4. The table will be picked up by the next scheduled `refresh_group` run.

## Testing Changes

```sql
-- Manual single-table refresh
SELECT etl.refresh_table('facility_facility');

-- Check status
SELECT * FROM etl.replication_status ORDER BY refresh_group, priority;

-- Check failures
SELECT * FROM etl.replication_runs WHERE status = 'failed' ORDER BY started_at DESC LIMIT 10;
```


