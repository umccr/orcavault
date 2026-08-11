{# Note - using S3 URI for generating hash key #}

{% macro generate_s3object_hk(bucket_col, key_col) %}

    sha2('s3://' || {{ bucket_col }} || '/' || {{ key_col }}, 256)

{% endmacro %}
