{% macro deploy_unload_schema() %}
  {% call statement('deploy_unload_schema', fetch_result=False) %}

    CREATE OR REPLACE PROCEDURE public.unload_schema(
        p_schema_name VARCHAR(100),
        s3_bucket_path VARCHAR(500),
        iam_role_arn VARCHAR(500)
    )
    LANGUAGE plpgsql
    AS $$
    DECLARE
        rec RECORD;
        v_sql_parquet VARCHAR(2000);
        v_sql_csv VARCHAR(2000);
        v_count INT;
    BEGIN
        -- 1. Security Check: Validate that the requested schema actually exists
        SELECT COUNT(*) INTO v_count
        FROM information_schema.schemata
        WHERE schema_name = p_schema_name;

        IF v_count = 0 THEN
            RAISE EXCEPTION 'Schema "%" does not exist in this database.', p_schema_name;
        END IF;

        -- 2. Loop through all base tables in the dynamically provided schema
        FOR rec IN
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = p_schema_name
              AND table_type = 'BASE TABLE'
        LOOP
            -- 3. PARQUET Unload syntax
            v_sql_parquet := 'UNLOAD (''SELECT * FROM ' || quote_ident(p_schema_name) || '.' || quote_ident(rec.table_name) || ''') ' ||
                             'TO ''' || s3_bucket_path || '/parquet/' || p_schema_name || '/' || rec.table_name || '/'' ' ||
                             'IAM_ROLE ''' || iam_role_arn || ''' ' ||
                             'FORMAT PARQUET ALLOWOVERWRITE;';

            RAISE INFO 'Unloading %.% to Parquet (Snappy)...', p_schema_name, rec.table_name;
            EXECUTE v_sql_parquet;

            -- 4. CSV Unload syntax (Removed EXTENSION parameter)
            v_sql_csv := 'UNLOAD (''SELECT * FROM ' || quote_ident(p_schema_name) || '.' || quote_ident(rec.table_name) || ''') ' ||
                         'TO ''' || s3_bucket_path || '/csv/' || p_schema_name || '/' || rec.table_name || '/' || rec.table_name || '_'' ' ||
                         'IAM_ROLE ''' || iam_role_arn || ''' ' ||
                         'FORMAT CSV HEADER GZIP ALLOWOVERWRITE MANIFEST;';

            RAISE INFO 'Unloading %.% to CSV (GZIP)...', p_schema_name, rec.table_name;
            EXECUTE v_sql_csv;

        END LOOP;

        RAISE INFO 'Schema "%" unload completed successfully.', p_schema_name;
    END;
    $$;

  {% endcall %}
{% endmacro %}
