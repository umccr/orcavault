{#
    The latest PSA version of every request must equal its current row in tsa.redcap__case.

    The model appends a new version whenever a record differs from its latest stored version. If it only
    compared against any earlier version, a record that reverted to an earlier value (A -> B -> A) would be
    skipped and PSA would keep B as the latest version while TSA says A. This test catches that.

    Returns one row per TSA record whose values are not matched by the latest PSA version. Only columns
    present in both tables are compared, so a TSA column the PSA table has not picked up yet is covered by
    assert_redcap_case_tsa_columns_captured instead. Records removed from TSA are ignored, because PSA
    never deletes.

    Run after the model: dbt build -s redcap__case
#}

{%- set src = source('tsa', 'redcap__case') -%}
{%- set psa = ref('redcap__case') -%}

{%- set columns = [] -%}
{%- if execute -%}
    {%- set psa_columns = [] -%}
    {%- for c in adapter.get_columns_in_relation(psa) -%}
        {%- do psa_columns.append(c.name | lower) -%}
    {%- endfor -%}
    {%- for c in adapter.get_columns_in_relation(src) -%}
        {%- if c.name | lower in psa_columns and c.name | lower not in ['load_datetime', 'record_source'] -%}
            {%- do columns.append(c.name | lower) -%}
        {%- endif -%}
    {%- endfor -%}
{%- endif -%}

with tsa as (

    select distinct
        {% for col in columns %}
        {{ adapter.quote(col) }}{{ ',' if not loop.last }}
        {% endfor %}
    from
        {{ src }}
    -- Same filter as the model: records where every column is null or empty are not loaded.
    where
        coalesce(
            {% for col in columns %}
            nullif(trim(cast({{ adapter.quote(col) }} as varchar)), ''){{ ',' if not loop.last }}
            {% endfor %}
        ) is not null

),

psa_latest as (

    select
        {% for col in columns %}
        {{ adapter.quote(col) }}{{ ',' if not loop.last }}
        {% endfor %}
    from (
        select
            *,
            row_number() over (
                partition by request_id
                order by load_datetime desc
            ) as _rn
        from
            {{ psa }}
    )
    where
        _rn = 1

)

-- TSA rows with no identical latest PSA version.
select
    *
from (
    select * from tsa
    except
    select * from psa_latest
)
