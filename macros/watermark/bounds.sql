{% macro watermark_bound(change_expression='load_datetime') %}
    {#-

    This calculates the bound for an incremental model's read. It picks a starting position,
    then keeps the rows whose `change_expression` is later than that position and not
    later than the run's `run_started_at`. The starting position is:

    1. If the target is empty, no lower bound, so everything is read.
    2. If nothing is stored in `meta.model_position`, the target's `max(load_datetime)`.
    3. If the target's current `max(load_datetime)` is below the stored `target_max_at_write`,
       rows were deleted and the stored position is no longer valid, so use the target's
       `max(load_datetime)`.
    4. Otherwise, the stored `position`.

    The stored position moves forward on every successful run, including a no load run. If it
    is missing or invalid, the fallback is correctly the target's own `max(load_datetime)`. This
    is safe because `load_datetime` is created inside the PSA models, and everything afterwards
    compares against the same warehouse clock. The PSA models themselves use the file path as the
    identity for what needs to be loaded.

    -#}

    {#- If this is not an incremental run, then don't add a bound. -#}
    {% if not is_incremental() %}
        {{ return('true') }}
    {% endif %}

    {% set stored_position %}
        (select p.position from meta.model_position p where p.model_id = '{{ model.unique_id }}')
    {%- endset %}
    {% set stored_max %}
        (select p.target_max_at_write from meta.model_position p where p.model_id = '{{ model.unique_id }}')
    {%- endset %}
    {% set target_max %}
        (select max(load_datetime) from {{ this }})
    {%- endset %}

    {#- Null only when the target is empty, which means no lower bound. -#}
    {% set lower_bound %}
        case
            when {{ stored_max }} is null
              or {{ target_max }} is null
              or {{ target_max }} < {{ stored_max }}
            then {{ target_max }}
            else {{ stored_position }}
        end
    {%- endset %}

    (
        (({{ change_expression }}) > {{ lower_bound }} or {{ lower_bound }} is null)
        {#- Check to make sure that the upper bound is also exact, only load up to what this
            specific run will cover. -#}
        and ({{ change_expression }}) <= cast('{{ run_started_at }}' as timestamptz)
    )
{% endmacro %}
