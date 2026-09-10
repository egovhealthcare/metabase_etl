# Recovery Runbook

Use this guide for failed FDW mappings, schema drift, and destructive rebuilds.
Use the [pause and resume commands](operations.md#pause-and-resume-schedules)
before changing schemas or rebuilding data.

## FDW Works as Admin but Fails in Cron

FDW connections are resolved per local database role. If an administrator can
run `etl.refresh_*()` but `warehouse_etl` cannot, inspect the ETL role's
foreign-server grant and user mapping before changing either object.

Reapply `sql/01-warehouse-fdw-setup.sql` using the
[documented variables](variables.md), then reapply
`sql/02-import-care-foreign-tables.sql`. Step `01` drops the foreign server
with `CASCADE`, so step `02` is required.

Do not paste a password into an ad hoc repair query.

Test the mapping:

```sql
SET ROLE warehouse_etl;

SELECT id
FROM replica.facility_facility
LIMIT 1;

SELECT etl.refresh_table('facility_facility');

RESET ROLE;
```

Do not grant all `raw` tables to `warehouse_etl`. The role owns tables created
by `etl.ensure_raw_table`; a non-owner attempting those grants will fail.

## Source Schema Drift

When the source adds, removes, or changes columns:

1. Pause cron schedules using the
   [operations runbook](operations.md#pause-and-resume-schedules).
2. Reapply `sql/02-import-care-foreign-tables.sql`.
3. Apply compatible `ALTER TABLE raw...` changes, or rebuild each incompatible
   raw table.
4. Run a manual refresh.
5. Confirm `etl.replication_status`.
6. Resume schedules.

Rebuild one raw table:

```sql
DROP TABLE IF EXISTS raw.emr_patient;
DELETE FROM etl.replication_state WHERE table_name = 'emr_patient';
SELECT etl.refresh_table('emr_patient');
```

This discards the local snapshot for that table. Confirm that the source can
serve a full reload before running it.

## Rebuild the Raw Schema

Use this only during initial setup or after a confirmed ownership/schema
failure affecting many tables. It removes every local raw table.

Before proceeding:

1. Pause cron schedules using the
   [operations runbook](operations.md#pause-and-resume-schedules).
2. Take a warehouse backup.
3. Record the current OpenTofu state version and deployed commit.
4. Confirm that the source replica can sustain a full reload.

Run on `metabase_warehouse`:

```sql
DROP SCHEMA IF EXISTS raw CASCADE;
CREATE SCHEMA raw;

GRANT USAGE, CREATE ON SCHEMA raw TO warehouse_etl;

TRUNCATE etl.replication_state;
TRUNCATE etl.replication_runs RESTART IDENTITY;
```

Then recreate data in stages:

```sql
SELECT etl.refresh_table('facility_facility');
SELECT etl.refresh_group('daily');
SELECT etl.refresh_group('hourly');
```

Tables created by the refresh functions are owned by `warehouse_etl`; no
additional blanket grant to that role is required.

## Failed OpenTofu Apply

The provisioning Job combines `psql -v ON_ERROR_STOP=1` with
`set -euo pipefail`. `ON_ERROR_STOP` makes `psql` stop the current file and
return a non-zero status; `set -e` then terminates the Job's shell before it
starts the next file. Preserve that ordering during recovery: fix the failure
and rerun the Job rather than starting from a later script.

1. Identify the failed numbered script from the masked apply log.
2. Inspect the Helm release and hook Job:

   ```sh
   export NAMESPACE="<gcp_template namespace_name>"
   helm status metabase --namespace="$NAMESPACE"
   helm history metabase --namespace="$NAMESPACE"
   kubectl get jobs --namespace="$NAMESPACE" \
     -l app.kubernetes.io/component=provision
   ```

3. Inspect PostgreSQL to determine which statements completed.
4. Fix the SQL in a reviewed commit and pin `metabase_etl_branch` to that
   commit.
5. Pause schedules with the
   [operations runbook](operations.md#pause-and-resume-schedules).
6. Generate and approve a new saved plan.
7. Reapply the exact plan artifact.
8. Run the post-apply checks in the
   [OpenTofu deployment guide](opentofu-deployment.md#post-apply-validation).
9. Resume schedules.

If Helm reports `failed` or `pending-upgrade` and blocks the next OpenTofu
apply, select a known-good revision from `helm history` and review the rollback
before running:

```sh
helm rollback metabase "<known-good-revision>" \
  --namespace="$NAMESPACE" \
  --wait \
  --timeout=7m
```

A rollback runs the provisioning hook again. Correct or pin the SQL ref before
rollback, retain the Helm history and Job logs, and generate a fresh reviewed
OpenTofu plan afterward to reconcile state.

`tofu destroy` does not undo database objects already applied by the Helm hook
Job.

## Roll Back

For a behavioral rollback:

1. Revert the SQL commit.
2. Review the reverse SQL diff.
3. Pause schedules with the
   [operations runbook](operations.md#pause-and-resume-schedules).
4. Create and approve a saved OpenTofu plan.
5. Apply that exact plan.
6. Verify refreshes and Metabase access.
7. Resume schedules.

For destructive cleanup, restore from the warehouse backup or run a
purpose-built, reviewed SQL migration. Do not assume that rerunning an older
setup script reverses later database changes.

## Remove the ETL Completely

The commands below permanently delete the replicated warehouse data and the
dedicated ETL roles and objects. They preserve the shared `pg_cron` and
`postgres_fdw` extensions.

`sql/01` creates `postgres_fdw` when it is absent, but removal intentionally
leaves it installed because the confirmed teardown boundary treats both
extensions as shared instance capabilities.

The following ownership boundary was confirmed for this deployment:

```text
Roles:   warehouse_fdw_reader, warehouse_etl, metabase_reader
Schemas: replica, raw, mart, etl
Server:  care_read_replica
```

Take database backups before continuing. The setup does not record previous
definitions, privileges, or owners for objects with these names.

### 1. Disable Future Provisioning

In the target `gcp_template` environment tfvars, set:

```hcl
metabase_etl_repo = null
```

Create and review a saved plan for the `deploy` stack, then apply that exact
plan. This prevents another Helm hook from recreating the database objects.

Disable the Metabase database connection before running the SQL below.

### 2. Remove Cron Jobs

Run on the warehouse `postgres` database as
`infra.outputs.metabase_database_user` from `gcp_template`. This is the user
embedded in `POSTGRES_URL`; `sql/05-pg-cron-schedules.sql` uses this connection
to create jobs whose execution username is `warehouse_etl`. Do not use a
different administrator: pg_cron role checks can hide the jobs or reject their
removal.

```sql
SELECT current_user;

SELECT jobid, jobname, username
FROM cron.job
WHERE jobname IN (
  'care-fdw-hourly-refresh',
  'care-fdw-daily-refresh',
  'care-fdw-clean-cron-history'
)
ORDER BY jobname;

BEGIN;

CREATE TEMP TABLE etl_cron_job_ids ON COMMIT DROP AS
SELECT jobid
FROM cron.job
WHERE jobname IN (
  'care-fdw-hourly-refresh',
  'care-fdw-daily-refresh',
  'care-fdw-clean-cron-history'
);

SELECT cron.unschedule(jobid)
FROM etl_cron_job_ids;

DELETE FROM cron.job_run_details
WHERE jobid IN (SELECT jobid FROM etl_cron_job_ids);

COMMIT;
```

Before `BEGIN`, confirm that `current_user` equals
`infra.outputs.metabase_database_user` and that the query lists the ETL jobs
with `username = 'warehouse_etl'`. Stop if those checks do not match.

### 3. Remove Warehouse Data and Roles

Run on `metabase_warehouse` as
`infra.outputs.metabase_database_user`, the user embedded in `WAREHOUSE_URL`.

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = current_database()
  AND usename IN ('warehouse_etl', 'metabase_reader')
  AND pid <> pg_backend_pid();

BEGIN;

SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '15min';

GRANT warehouse_etl TO CURRENT_USER;
GRANT metabase_reader TO CURRENT_USER;

DROP SERVER IF EXISTS care_read_replica CASCADE;
DROP SCHEMA IF EXISTS replica CASCADE;
DROP SCHEMA IF EXISTS raw CASCADE;
DROP SCHEMA IF EXISTS mart CASCADE;
DROP SCHEMA IF EXISTS etl CASCADE;

DROP OWNED BY metabase_reader;
DROP ROLE metabase_reader;

DROP OWNED BY warehouse_etl;
DROP ROLE warehouse_etl;

COMMIT;
```

If `DROP ROLE` reports dependencies in another warehouse database, connect to
that database, confirm those grants or objects are ETL-owned, run
`DROP OWNED BY <role>`, and rerun this block.

### 4. Remove the Source Reader

Run on the CARE source primary database as `infra.outputs.database_user`, the
user embedded in `CARE_SOURCE_URL` and used by the Job to run `sql/00`.

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE usename = 'warehouse_fdw_reader'
  AND pid <> pg_backend_pid();

BEGIN;

GRANT warehouse_fdw_reader TO CURRENT_USER;
DROP OWNED BY warehouse_fdw_reader;
DROP ROLE warehouse_fdw_reader;

COMMIT;
```

If `DROP ROLE` reports dependencies in another source database, connect to
that database, confirm those grants or objects are ETL-owned, run
`DROP OWNED BY warehouse_fdw_reader`, and rerun this block.

If the error names default privileges owned by a different role, the source
reader was configured outside the documented Job. Run the following as the
role named in that error before retrying:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE <original-grantor> IN SCHEMA public
REVOKE SELECT ON TABLES FROM warehouse_fdw_reader;
```

### 5. Verify

On the warehouse `postgres` database, reconnect as
`infra.outputs.metabase_database_user`:

```sql
SELECT current_user;

SELECT jobname, username
FROM cron.job
WHERE jobname IN (
  'care-fdw-hourly-refresh',
  'care-fdw-daily-refresh',
  'care-fdw-clean-cron-history'
);
```

The first query must show `infra.outputs.metabase_database_user`; only then
does an empty job result verify removal under pg_cron row-level security.

On `metabase_warehouse`:

```sql
SELECT rolname
FROM pg_roles
WHERE rolname IN ('warehouse_etl', 'metabase_reader');

SELECT nspname
FROM pg_namespace
WHERE nspname IN ('replica', 'raw', 'mart', 'etl');

SELECT srvname
FROM pg_foreign_server
WHERE srvname = 'care_read_replica';
```

On the CARE source primary:

```sql
SELECT rolname
FROM pg_roles
WHERE rolname = 'warehouse_fdw_reader';
```

All verification queries must return zero rows. The OpenTofu-generated
passwords remain in the `keys` state because `gcp_template#28` creates them
independently of `metabase_etl_repo`; do not destroy the shared KMS stack.
