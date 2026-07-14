{% macro generate_hash_diff(columns) %}
    sha2(
        {% for col in columns %}
            sha2(coalesce(cast({{ col }} as varchar), ''), 256)
            {% if not loop.last %} || {% endif %}
        {% endfor %}
    , 256)
{% endmacro %}
