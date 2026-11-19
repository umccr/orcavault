{% macro run_unload_schema(
    schema_name,
    s3_bucket_path,
    iam_role_arn
) %}

  {% call statement('run_unload_schema', fetch_result=False) %}

    CALL public.unload_schema(
      '{{ schema_name }}',
      '{{ s3_bucket_path }}',
      '{{ iam_role_arn }}'
    );

  {% endcall %}

{% endmacro %}
