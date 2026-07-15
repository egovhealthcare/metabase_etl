# Setting Up the Reporting Warehouse via GCP Cloud SQL Studio

Step-by-step guide to deploy the FDW-based reporting warehouse using **Cloud SQL Studio** (the SQL editor in Google Cloud Console).

---

## Prerequisites

Before you begin, ensure:

- [ ] You have two Cloud SQL for PostgreSQL instances:
  - **Source**: The CARE EMR database (or its read replica)
  - **Warehouse**: A separate instance for reporting
- [ ] Both instances are in the **same VPC** (or have private IP connectivity between them)
- [ ] You have the **private IP** of the source read replica (find it on the instance Overview page)
- [ ] You have **Cloud SQL Admin** or **Editor** IAM permissions on both instances
- [ ] The Cloud SQL flag `cloudsql.enable_pg_cron` is set to `on` on the **warehouse** instance (required for Step 6)

### How to Set the pg_cron Flag

1. Go to **Cloud SQL → Warehouse Instance → Edit**
2. Under **Flags**, click **Add a database flag**
3. Select `cloudsql.enable_pg_cron`, set value to `on`
4. Click **Save** (instance will restart)

---

## Step 1: Create the Read-Only User on the Source DB

> **Target**: Source primary instance  
> **Database**: `care` (or your source database name)  
> **Run as**: `postgres` (the default Cloud SQL admin user)

1. Open **Cloud SQL Studio** for your **source** instance
2. Select database: `care`
3. Paste and run the following (replace the password first):

```sql
CREATE ROLE warehouse_fdw_reader
  LOGIN
  PASSWORD 'CHANGE_ME_STRONG_PASSWORD'   -- ← Replace with a real password
  CONNECTION LIMIT 2;

GRANT CONNECT ON DATABASE care TO warehouse_fdw_reader;
GRANT USAGE ON SCHEMA public TO warehouse_fdw_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO warehouse_fdw_reader;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO warehouse_fdw_reader;

ALTER ROLE warehouse_fdw_reader SET statement_timeout = '5min';
ALTER ROLE warehouse_fdw_reader SET idle_in_transaction_session_timeout = '1min';
```

4. Verify: `SELECT rolname FROM pg_roles WHERE rolname = 'warehouse_fdw_reader';`

> **Note**: Roles replicate automatically to read replicas on Cloud SQL, so you only need to do this on the primary.

---

## Step 2: Set Up the FDW on the Warehouse

> **Target**: Warehouse instance  
> **Database**: `warehouse` (or whatever you named it)  
> **Run as**: `postgres`

1. Open **Cloud SQL Studio** for your **warehouse** instance
2. Select database: `warehouse`
3. Run the following (replace the 3 placeholders):

```sql
-- Enable the FDW extension
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- Create schemas
CREATE SCHEMA IF NOT EXISTS replica;
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE SCHEMA IF NOT EXISTS etl;

-- Create the ETL execution role
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'warehouse_etl') THEN
    CREATE ROLE warehouse_etl LOGIN PASSWORD 'CHANGE_ME_WAREHOUSE_ETL_PASSWORD';  -- ← Replace
  END IF;
END;
$$;

GRANT CONNECT ON DATABASE warehouse TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA replica TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA raw TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA mart TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA etl TO warehouse_etl;

-- Create the foreign server pointing to the source read replica
DROP SERVER IF EXISTS care_read_replica CASCADE;

CREATE SERVER care_read_replica
FOREIGN DATA WRAPPER postgres_fdw
OPTIONS (
  host 'READ_REPLICA_PRIVATE_IP',         -- ← Replace with source read replica private IP
  port '5432',
  dbname 'care',
  fetch_size '10000'
);

GRANT USAGE ON FOREIGN SERVER care_read_replica TO warehouse_etl;

-- User mapping for the ETL role
DROP USER MAPPING IF EXISTS FOR warehouse_etl SERVER care_read_replica;

CREATE USER MAPPING FOR warehouse_etl
SERVER care_read_replica
OPTIONS (
  user 'warehouse_fdw_reader',
  password 'CHANGE_ME_SOURCE_READER_PASSWORD'  -- ← Same password from Step 1
);

-- User mapping for the admin user (useful for testing)
DROP USER MAPPING IF EXISTS FOR CURRENT_USER SERVER care_read_replica;

CREATE USER MAPPING FOR CURRENT_USER
SERVER care_read_replica
OPTIONS (
  user 'warehouse_fdw_reader',
  password 'CHANGE_ME_SOURCE_READER_PASSWORD'  -- ← Same password from Step 1
);
```

4. **Test the connection** (still as postgres):

```sql
SELECT * FROM dblink('care_read_replica', 'SELECT 1') AS t(col int);
-- If this errors, check VPC connectivity / private IP / firewall rules
```

---

## Step 3: Import Foreign Tables

> **Target**: Warehouse instance  
> **Database**: `warehouse`  
> **Run as**: `postgres`

1. Still in Cloud SQL Studio on the warehouse, run:

```sql
DROP SCHEMA IF EXISTS replica CASCADE;
CREATE SCHEMA replica;

IMPORT FOREIGN SCHEMA public
LIMIT TO (
  facility_facility,
  facility_facilityflag,
  facility_patientmobileotp,
  emr_account,
  emr_activitydefinition,
  emr_allergyintolerance,
  emr_chargeitem,
  emr_chargeitemdefinition,
  emr_condition,
  emr_consent,
  emr_device,
  emr_deviceencounterhistory,
  emr_devicelocationhistory,
  emr_deviceservicehistory,
  emr_diagnosticreport,
  emr_encounter,
  emr_encounterorganization,
  emr_facilitymonetoryconfig,
  emr_userresourcefavorites,
  emr_fileupload,
  emr_healthcareservice,
  emr_inventoryitem,
  emr_invoice,
  emr_facilitylocation,
  emr_facilitylocationorganization,
  emr_facilitylocationencounter,
  emr_medicationadministration,
  emr_medicationdispense,
  emr_dispenseorder,
  emr_medicationrequestprescription,
  emr_medicationrequest,
  emr_medicationstatement,
  emr_metaartifact,
  emr_notethread,
  emr_notemessage,
  emr_observation,
  emr_observationdefinition,
  emr_facilityorganization,
  emr_organization,
  emr_organizationuser,
  emr_facilityorganizationuser,
  emr_patient,
  emr_patientorganization,
  emr_patientuser,
  emr_patientidentifierconfig,
  emr_patientidentifier,
  emr_paymentreconciliation,
  emr_product,
  emr_productknowledge,
  emr_questionnairetag,
  emr_questionnaire,
  emr_formsubmission,
  emr_questionnaireresponse,
  emr_questionnaireorganization,
  emr_questionnairefacilityorganization,
  emr_questionnaireresponsetemplate,
  emr_reportupload,
  emr_template,
  emr_resourcecategory,
  emr_resourcerequest,
  emr_resourcerequestcomment,
  emr_tokenslot,
  emr_tokenbooking,
  emr_schedulableresource,
  emr_schedule,
  emr_availability,
  emr_availabilityexception,
  emr_tokenqueue,
  emr_tokensubqueue,
  emr_tokencategory,
  emr_token,
  emr_servicerequest,
  emr_specimen,
  emr_specimendefinition,
  emr_supplydelivery,
  emr_deliveryorder,
  emr_supplyrequest,
  emr_requestorder,
  emr_tagconfig,
  emr_valueset,
  emr_uservaluesetpreference
)
FROM SERVER care_read_replica
INTO replica;

GRANT USAGE ON SCHEMA replica TO warehouse_etl;
GRANT SELECT ON ALL TABLES IN SCHEMA replica TO warehouse_etl;
```

2. **Verify** (should return rows from the source):

```sql
SELECT count(*) FROM replica.facility_facility;
```

> **Troubleshooting**: If a specific table doesn't exist in the source deployment, remove it from the `LIMIT TO` list and rerun.

---

## Step 4: Create ETL Functions and State Tables

> **Target**: Warehouse instance  
> **Database**: `warehouse`  
> **Run as**: `postgres`

1. Open the file `sql/03-etl-functions.sql` from this repository
2. Copy the **entire contents** and paste into Cloud SQL Studio
3. Click **Run**

4. **Verify** the objects were created:

```sql
-- Tables created
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'etl' ORDER BY table_name;
-- Should show: replication_runs, replication_state, replication_tables

-- Functions created
SELECT routine_name FROM information_schema.routines
WHERE routine_schema = 'etl' ORDER BY routine_name;
-- Should show: column_exists, ensure_raw_table, full_refresh_table,
--              incremental_refresh_table, refresh_group, refresh_table

-- View created
SELECT viewname FROM pg_views WHERE schemaname = 'etl';
-- Should show: replication_status
```

---

## Step 5: Register All Tables

> **Target**: Warehouse instance  
> **Database**: `warehouse`  
> **Run as**: `postgres`

1. Open the file `sql/04-register-care-tables.sql` from this repository
2. Copy the **entire contents** and paste into Cloud SQL Studio
3. Click **Run**

4. **Verify**:

```sql
SELECT count(*) FROM etl.replication_tables;
-- Should return ~77 rows

SELECT refresh_group, refresh_mode, count(*)
FROM etl.replication_tables
WHERE enabled
GROUP BY refresh_group, refresh_mode
ORDER BY 1, 2;
```

---

## Step 6: Run the First Manual Refresh (Test)

> **Target**: Warehouse instance  
> **Database**: `warehouse`  
> **Run as**: `postgres`

Before enabling cron, verify the ETL works end-to-end:

```sql
-- Test a single small table first
SELECT etl.refresh_table('facility_facility');

-- Check that data landed in raw
SELECT count(*) FROM raw.facility_facility;

-- Check the run log
SELECT * FROM etl.replication_runs ORDER BY started_at DESC LIMIT 5;
```

If that succeeds, do a full group:

```sql
-- This will take a few minutes for the first run (all tables are empty)
SELECT etl.refresh_group('daily');
SELECT etl.refresh_group('hourly');
```

**Check for failures**:

```sql
SELECT table_name, status, error_message
FROM etl.replication_runs
WHERE status = 'failed'
ORDER BY started_at DESC
LIMIT 20;
```

> **Common errors**:
> - `relation "replica.xxx" does not exist` → table missing from Step 3, remove from registry or re-import
> - `timeout` → source is slow; try again off-peak or increase `statement_timeout` temporarily

---

## Step 7: Set Up Cron Schedules

> **Target**: Warehouse instance  
> **Database**: `postgres` (pg_cron runs from the postgres database)  
> **Run as**: `postgres`

⚠️ **Important**: Switch to the `postgres` database in Cloud SQL Studio (use the database dropdown at the top).

1. Run:

```sql
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
```

2. **Verify schedules**:

```sql
SELECT jobid, jobname, schedule, database, username, active
FROM cron.job
ORDER BY jobname;
```

You should see 3 jobs listed.

3. **Check cron runs** (after the next `:07` mark):

```sql
SELECT jobid, status, return_message, start_time, end_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 10;
```

---

## Step 8: Create the Metabase Reader Role

> **Target**: Warehouse instance  
> **Database**: `warehouse`  
> **Run as**: `postgres`

Switch back to the `warehouse` database, then run:

```sql
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'metabase_reader') THEN
    CREATE ROLE metabase_reader LOGIN PASSWORD 'CHANGE_ME_METABASE_PASSWORD';  -- ← Replace
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
```

> ⚠️ **Do NOT grant access to `replica.*`** — that would route Metabase queries through FDW directly to the source and overload it.

---

## Step 9: Connect Metabase

In your Metabase instance:

1. Go to **Admin → Databases → Add database**
2. Fill in:
   - **Type**: PostgreSQL
   - **Host**: Warehouse instance private IP (or Cloud SQL Auth Proxy address)
   - **Port**: 5432
   - **Database**: `warehouse`
   - **Username**: `metabase_reader`
   - **Password**: (the password you set in Step 8)
3. Click **Save**
4. Metabase will sync metadata — you should see schemas `raw` and `mart`

---

## Post-Setup Verification Checklist

Run these on the **warehouse** in Cloud SQL Studio to confirm everything is healthy:

```sql
-- 1. All tables refreshing successfully?
SELECT * FROM etl.replication_status
ORDER BY refresh_group, priority;

-- 2. Any recent failures?
SELECT table_name, started_at, error_message
FROM etl.replication_runs
WHERE status = 'failed'
  AND started_at > now() - interval '24 hours'
ORDER BY started_at DESC;

-- 3. Cron jobs running?  (run from 'postgres' database)
SELECT jobname, status, return_message, start_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 10;

-- 4. Row counts look reasonable?
SELECT table_name, last_rows_affected, last_success_at
FROM etl.replication_state
ORDER BY table_name;
```

---

## Quick Reference: Which Database to Use

| Step | Cloud SQL Instance | Database to Select |
|------|--------------------|--------------------|
| 1 | Source (primary) | `care` |
| 2–6, 8 | Warehouse | `warehouse` |
| 7 | Warehouse | `postgres` |

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| `could not connect to server` in Step 2 | VPC/firewall blocks traffic between instances | Ensure both are on same VPC; check authorized networks |
| `permission denied for relation` | User mapping issue | Verify `warehouse_fdw_reader` has SELECT grants on source |
| `relation "replica.xxx" does not exist` | Table not in source schema | Remove from `LIMIT TO` list in Step 3 and from registry |
| `pg_cron extension not available` | Flag not set | Set `cloudsql.enable_pg_cron=on` flag and restart instance |
| Cron shows `failed` with permission error | `warehouse_etl` role missing grants | Re-run the GRANT statements from Steps 2–4 |
| Metabase can't connect | Wrong IP or password | Use private IP; verify `metabase_reader` password |
| Incremental refresh missing rows | Replica lag > lookback | Increase lookback: `UPDATE etl.replication_tables SET lookback = '6 hours' WHERE ...` |
