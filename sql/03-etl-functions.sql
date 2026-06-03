-- Run on the warehouse database.

CREATE TABLE IF NOT EXISTS etl.replication_tables (
  table_name text PRIMARY KEY,
  refresh_mode text NOT NULL CHECK (refresh_mode IN ('full', 'incremental')),
  refresh_group text NOT NULL DEFAULT 'hourly',
  enabled boolean NOT NULL DEFAULT true,
  include_deleted boolean NOT NULL DEFAULT true,
  lookback interval NOT NULL DEFAULT interval '2 hours',
  priority integer NOT NULL DEFAULT 100,
  notes text
);

CREATE TABLE IF NOT EXISTS etl.replication_state (
  table_name text PRIMARY KEY REFERENCES etl.replication_tables(table_name),
  last_success_at timestamptz,
  last_successful_modified_date timestamptz,
  last_rows_affected bigint,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS etl.replication_runs (
  run_id bigserial PRIMARY KEY,
  table_name text NOT NULL,
  refresh_mode text,
  refresh_group text,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finished_at timestamptz,
  status text NOT NULL CHECK (status IN ('running', 'success', 'failed')),
  rows_affected bigint,
  error_message text
);

CREATE OR REPLACE FUNCTION etl.column_exists(
  p_schema text,
  p_table_name text,
  p_column_name text
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = p_schema
      AND table_name = p_table_name
      AND column_name = p_column_name
  );
$$;

CREATE OR REPLACE FUNCTION etl.ensure_raw_table(p_table_name text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_raw_table regclass;
  v_has_id boolean;
  v_has_pk boolean;
  v_pkey_name text;
BEGIN
  IF to_regclass(format('replica.%I', p_table_name)) IS NULL THEN
    RAISE EXCEPTION 'Foreign table replica.% does not exist', p_table_name;
  END IF;

  IF to_regclass(format('raw.%I', p_table_name)) IS NULL THEN
    EXECUTE format(
      'CREATE TABLE raw.%I AS SELECT * FROM replica.%I WHERE false',
      p_table_name,
      p_table_name
    );
  END IF;

  SELECT to_regclass(format('raw.%I', p_table_name)) INTO v_raw_table;

  SELECT etl.column_exists('raw', p_table_name, 'id') INTO v_has_id;
  IF v_has_id THEN
    SELECT EXISTS (
      SELECT 1
      FROM pg_index
      WHERE indrelid = v_raw_table
        AND indisprimary
    )
    INTO v_has_pk;

    IF NOT v_has_pk THEN
      v_pkey_name := left(p_table_name || '_pkey', 63);
      EXECUTE format(
        'ALTER TABLE raw.%I ADD CONSTRAINT %I PRIMARY KEY (id)',
        p_table_name,
        v_pkey_name
      );
    END IF;
  END IF;

  IF etl.column_exists('raw', p_table_name, 'modified_date') THEN
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I ON raw.%I (modified_date)',
      left(p_table_name || '_modified_date_idx', 63),
      p_table_name
    );
  END IF;

  IF etl.column_exists('raw', p_table_name, 'deleted') THEN
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I ON raw.%I (deleted)',
      left(p_table_name || '_deleted_idx', 63),
      p_table_name
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION etl.full_refresh_table(
  p_table_name text,
  p_include_deleted boolean DEFAULT true
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_rows bigint := 0;
  v_where text := '';
  v_watermark timestamptz;
BEGIN
  PERFORM etl.ensure_raw_table(p_table_name);

  IF NOT p_include_deleted AND etl.column_exists('replica', p_table_name, 'deleted') THEN
    v_where := ' WHERE deleted = false';
  END IF;

  EXECUTE format('TRUNCATE TABLE raw.%I', p_table_name);
  EXECUTE format(
    'INSERT INTO raw.%I SELECT * FROM replica.%I%s',
    p_table_name,
    p_table_name,
    v_where
  );
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF etl.column_exists('raw', p_table_name, 'modified_date') THEN
    EXECUTE format('SELECT max(modified_date) FROM raw.%I', p_table_name)
    INTO v_watermark;
  END IF;

  INSERT INTO etl.replication_state (
    table_name,
    last_success_at,
    last_successful_modified_date,
    last_rows_affected,
    updated_at
  )
  VALUES (p_table_name, clock_timestamp(), v_watermark, v_rows, clock_timestamp())
  ON CONFLICT (table_name) DO UPDATE SET
    last_success_at = EXCLUDED.last_success_at,
    last_successful_modified_date = EXCLUDED.last_successful_modified_date,
    last_rows_affected = EXCLUDED.last_rows_affected,
    updated_at = EXCLUDED.updated_at;

  EXECUTE format('ANALYZE raw.%I', p_table_name);
  RETURN v_rows;
END;
$$;

CREATE OR REPLACE FUNCTION etl.incremental_refresh_table(
  p_table_name text,
  p_lookback interval DEFAULT interval '2 hours',
  p_include_deleted boolean DEFAULT true
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_rows bigint := 0;
  v_watermark timestamptz;
  v_lower_bound timestamptz;
  v_new_watermark timestamptz;
  v_columns text;
  v_update_list text;
  v_deleted_filter text := '';
BEGIN
  PERFORM etl.ensure_raw_table(p_table_name);

  IF NOT etl.column_exists('replica', p_table_name, 'modified_date') THEN
    RETURN etl.full_refresh_table(p_table_name, p_include_deleted);
  END IF;

  SELECT last_successful_modified_date
  INTO v_watermark
  FROM etl.replication_state
  WHERE table_name = p_table_name;

  v_lower_bound := COALESCE(v_watermark, '1970-01-01'::timestamptz) - p_lookback;

  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
  INTO v_columns
  FROM information_schema.columns
  WHERE table_schema = 'raw'
    AND table_name = p_table_name;

  SELECT string_agg(
    format('%1$I = EXCLUDED.%1$I', column_name),
    ', '
    ORDER BY ordinal_position
  )
  INTO v_update_list
  FROM information_schema.columns
  WHERE table_schema = 'raw'
    AND table_name = p_table_name
    AND column_name <> 'id';

  IF v_columns IS NULL THEN
    RAISE EXCEPTION 'No columns found for raw.%', p_table_name;
  END IF;

  IF v_update_list IS NULL THEN
    v_update_list := 'id = EXCLUDED.id';
  END IF;

  IF NOT p_include_deleted AND etl.column_exists('replica', p_table_name, 'deleted') THEN
    v_deleted_filter := ' AND deleted = false';
  END IF;

  EXECUTE format(
    'INSERT INTO raw.%1$I (%2$s)
     SELECT %2$s
     FROM replica.%1$I
     WHERE modified_date >= $1%3$s
     ON CONFLICT (id) DO UPDATE SET %4$s',
    p_table_name,
    v_columns,
    v_deleted_filter,
    v_update_list
  )
  USING v_lower_bound;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  EXECUTE format('SELECT max(modified_date) FROM raw.%I', p_table_name)
  INTO v_new_watermark;

  INSERT INTO etl.replication_state (
    table_name,
    last_success_at,
    last_successful_modified_date,
    last_rows_affected,
    updated_at
  )
  VALUES (p_table_name, clock_timestamp(), v_new_watermark, v_rows, clock_timestamp())
  ON CONFLICT (table_name) DO UPDATE SET
    last_success_at = EXCLUDED.last_success_at,
    last_successful_modified_date = EXCLUDED.last_successful_modified_date,
    last_rows_affected = EXCLUDED.last_rows_affected,
    updated_at = EXCLUDED.updated_at;

  EXECUTE format('ANALYZE raw.%I', p_table_name);
  RETURN v_rows;
END;
$$;

CREATE OR REPLACE FUNCTION etl.refresh_table(p_table_name text)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_config etl.replication_tables%ROWTYPE;
  v_run_id bigint;
  v_rows bigint := 0;
BEGIN
  SELECT *
  INTO v_config
  FROM etl.replication_tables
  WHERE table_name = p_table_name;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Table % is not registered in etl.replication_tables', p_table_name;
  END IF;

  IF NOT v_config.enabled THEN
    RAISE NOTICE 'Skipping disabled replication table %', p_table_name;
    RETURN 0;
  END IF;

  INSERT INTO etl.replication_runs (
    table_name,
    refresh_mode,
    refresh_group,
    status
  )
  VALUES (
    p_table_name,
    v_config.refresh_mode,
    v_config.refresh_group,
    'running'
  )
  RETURNING run_id INTO v_run_id;

  IF v_config.refresh_mode = 'full' THEN
    v_rows := etl.full_refresh_table(p_table_name, v_config.include_deleted);
  ELSE
    v_rows := etl.incremental_refresh_table(
      p_table_name,
      v_config.lookback,
      v_config.include_deleted
    );
  END IF;

  UPDATE etl.replication_runs
  SET status = 'success',
      finished_at = clock_timestamp(),
      rows_affected = v_rows
  WHERE run_id = v_run_id;

  RETURN v_rows;
EXCEPTION WHEN OTHERS THEN
  IF v_run_id IS NOT NULL THEN
    UPDATE etl.replication_runs
    SET status = 'failed',
        finished_at = clock_timestamp(),
        error_message = SQLERRM
    WHERE run_id = v_run_id;
  END IF;
  RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION etl.refresh_group(p_refresh_group text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_table record;
BEGIN
  FOR v_table IN
    SELECT table_name
    FROM etl.replication_tables
    WHERE refresh_group = p_refresh_group
      AND enabled
    ORDER BY priority, table_name
  LOOP
    PERFORM etl.refresh_table(v_table.table_name);
  END LOOP;
END;
$$;

CREATE OR REPLACE VIEW etl.replication_status AS
SELECT
  t.table_name,
  t.refresh_mode,
  t.refresh_group,
  t.enabled,
  t.lookback,
  s.last_success_at,
  s.last_successful_modified_date,
  s.last_rows_affected,
  r.status AS last_run_status,
  r.error_message AS last_run_error
FROM etl.replication_tables t
LEFT JOIN etl.replication_state s ON s.table_name = t.table_name
LEFT JOIN LATERAL (
  SELECT status, error_message
  FROM etl.replication_runs r
  WHERE r.table_name = t.table_name
  ORDER BY r.started_at DESC
  LIMIT 1
) r ON true;

GRANT USAGE ON SCHEMA etl TO warehouse_etl;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA etl TO warehouse_etl;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA etl TO warehouse_etl;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA etl TO warehouse_etl;
GRANT USAGE, CREATE ON SCHEMA raw TO warehouse_etl;

