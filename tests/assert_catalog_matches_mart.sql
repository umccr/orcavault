{#

    The mart catalog (seed dictionary__data_mart_catalog) must list exactly the tables
    built in the mart schema. Returns a row for each mismatch:
      - in_catalog_only: catalog entry without a relation in the mart schema
      - in_mart_only:    mart relation missing from the catalog (`catalog` itself is excluded)

    The mart schema is resolved from ref('catalog'), so personal targets compare against
    their own prefixed mart schema.

#}
with catalog as (

    select table_name from {{ ref('catalog') }}

),

mart as (

    {# svv_tables, not information_schema.tables: the latter is leader-node only and cannot be combined with user tables on Redshift. #}
    select table_name
    from svv_tables
    where table_schema = '{{ ref("catalog").schema }}'
      and table_name <> '{{ ref("catalog").identifier }}'

)

select 'in_catalog_only' as mismatch, table_name
from catalog
where table_name not in ( select table_name from mart )

union all

select 'in_mart_only' as mismatch, table_name
from mart
where table_name not in ( select table_name from catalog )
