{{
    config(
        materialized='ephemeral'
    )
}}

{#

This is the latest row of each association up to `pending`, like `int_cdc_state`, except it also includes deletes of
the association. The delete keeps its `op`, so a model can tell that the association has ended.

#}

select * from (
    select
        orcabus_id,
        {{ cdc_fill_delete('library_id') }}         as library_id,
        {{ cdc_fill_delete('sequence_id') }}        as sequence_id,
        association_date,
        status,
        op,
        _dms_cdc_timestamp,
        row_number() over (
            partition by orcabus_id
            order by _dms_cdc_timestamp desc, case when op = 'D' then 1 else 0 end desc
        ) as rn,
        {{ cdc_window('orcabus_sequence_run_manager', 'sequence_run_manager_libraryassociation') }} as cdc_changed
    from {{ source('orcabus_sequence_run_manager', 'sequence_run_manager_libraryassociation') }}
    where {{ cdc_upper_bound('orcabus_sequence_run_manager', 'sequence_run_manager_libraryassociation') }}
) t
where rn = 1
