{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='append_new_columns'
    )
}}

{#
    Persistent history of the REDCap case records.

    Every source column is compared with the persisted history (EXCEPT), so any changed value appends the
    changed record as a new version. Unchanged records are skipped. Records where every column is null or
    empty are ignored. EXCEPT also removes exact duplicate rows within one snapshot. Change the column
    list only together with a rebuild of this model, because existing history will not match the new list.
#}

{% set columns = [
    "request_id",
    "request_id_sk",
    "individual_id",
    "rf_consent_signed",
    "identified",
    "rf_study",
    "rf_study_id",
    "rf_timepoint",
    "institution_code",
    "rf_ur",
    "rf_sex",
    "rf_patient_gender_spcu",
    "rf_diagnosis",
    "rf_test_requested",
    "rf_cttso_sample_type",
    "rf_cttso_dna_sample_id",
    "rf_cttso_collect_date",
    "rf_cttso_collect_time",
    "cttso_receipt_date",
    "cttso_receipt_time",
    "cgw_mrn",
    "cgw_snomed_disease_code",
    "cgw_specimen",
    "cgw_sample_type",
    "cgw_is_identified",
    "cgw_is_identifed",
    "cgw_panel",
    "cttso_sample_id",
    "cttso_library_id",
    "cttso_prid",
    "cttso_curation_status",
    "cttso_accession_id",
    "rf_tumour_sample_type",
    "rf_tumour_dna_sample_id",
    "rf_tumour_rna_sample_id",
    "rf_tumour_collect_date",
    "rf_tumour_biopsy_site",
    "rf_germline_sample_type",
    "rf_germline_dna_sample_id",
    "rf_germline_collect_date",
    "tumour_receipt_date",
    "report_due_date",
    "nata_accred_report",
    "rnasum_reference___pancan",
    "rnasum_reference___acc",
    "rnasum_reference___blca",
    "rnasum_reference___blca_net",
    "rnasum_reference___brca",
    "rnasum_reference___cesc",
    "rnasum_reference___chol",
    "rnasum_reference___coad",
    "rnasum_reference___dlbc",
    "rnasum_reference___esca",
    "rnasum_reference___gbm",
    "rnasum_reference___hnsc",
    "rnasum_reference___kich",
    "rnasum_reference___kirc",
    "rnasum_reference___kirp",
    "rnasum_reference___laml",
    "rnasum_reference___lgg",
    "rnasum_reference___lihc",
    "rnasum_reference___luad",
    "rnasum_reference___lusc",
    "rnasum_reference___meso",
    "rnasum_reference___ov",
    "rnasum_reference___paad",
    "rnasum_reference___pcpg",
    "rnasum_reference___prad",
    "rnasum_reference___read",
    "rnasum_reference___sarc",
    "rnasum_reference___skcm",
    "rnasum_reference___stad",
    "rnasum_reference___tgct",
    "rnasum_reference___thca",
    "rnasum_reference___thym",
    "rnasum_reference___ucec",
    "rnasum_reference___ucs",
    "rnasum_reference___uvm",
    "rnasum_reference___luad_lcnec",
    "rnasum_reference___paad_acc",
    "rnasum_reference___paad_ipmn",
    "rnasum_reference___paad_net",
    "germline_receipt_date",
    "qci_diagnosis_term",
    "qci_tumour_sample_type",
    "qci_primary_tumor_site",
    "qci_germline_sample_type",
    "tumour_sample_id",
    "tumour_library_id",
    "wgs_tumour_prid",
    "wgs_analysis_id",
    "tumour_curation_status",
    "qci_somatic_dp_id",
    "qci_somatic_accession_id",
    "qci_somatic_accession_url",
    "germline_sample_id",
    "germline_library_id",
    "wgs_germline_prid",
    "germline_curation_status",
    "qci_germline_dp_id",
    "qci_germline_accession_id",
    "qci_germline_accession_url",
    "legacy_order_id",
    "wts_sample_id",
    "wts_library_id",
    "wts_prid",
    "wts_curation_status",
    "request_alias",
    "rf_comments",
    "request_entry_complete",
    "internal_details_complete",
    "test_request_complete"
] %}

with source as (

    select
        {% for col in columns %}
        {{ col }}{{ ',' if not loop.last }}
        {% endfor %}
    from
        {{ source('tsa', 'redcap__case') }}
    -- Skip records where every column is null or empty.
    where
        coalesce(
            {% for col in columns %}
            nullif(trim(cast({{ col }} as varchar)), ''){{ ',' if not loop.last }}
            {% endfor %}
        ) is not null

),

differentiated as (

    select
        *
    from
        source
    {% if is_incremental() %}
    -- EXCEPT compares every column and treats nulls as equal, so only new or changed records remain.
    except
    select
        {% for col in columns %}
        {{ col }}{{ ',' if not loop.last }}
        {% endfor %}
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        *,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        cast('redcap__case' as varchar(255)) as record_source
    from
        differentiated

),

final as (

    select * from transformed

)

select * from final
