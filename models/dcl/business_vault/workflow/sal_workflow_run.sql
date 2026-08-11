{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='sal_workflow_run_hk',
        on_schema_change='fail',
        dist='sal_workflow_run_hk',
        sort=['sal_workflow_run_hk', 'load_datetime']
    )
}}

with source as (

    select *
    from {{ ref('mdm__workflow_run') }}
    {% if is_incremental() %}
    where ( select count(1) from {{ ref('mdm__workflow_run') }} ) > 0
    {% endif %}

),

transformed as (

    select
        sha2(base_portal_run_id::varchar, 256)      as base_workflow_run_hk,
        sha2(alias_portal_run_id::varchar, 256)     as alias_workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'mdm__workflow_run'                         as record_source,
        base_portal_run_id,
        alias_portal_run_id
    from source

),

final as (

    select
        cast({{ generate_hash_diff(['base_workflow_run_hk', 'alias_workflow_run_hk']) }}
                                            as char(64))     as sal_workflow_run_hk,
        cast(base_workflow_run_hk           as char(64))     as base_workflow_run_hk,
        cast(alias_workflow_run_hk          as char(64))     as alias_workflow_run_hk,
        cast(load_datetime                  as timestamptz)  as load_datetime,
        cast(record_source                  as varchar(100)) as record_source,
        cast(base_portal_run_id             as char(16))     as base_portal_run_id,
        cast(alias_portal_run_id            as char(16))     as alias_portal_run_id
    from transformed

)

select * from final
