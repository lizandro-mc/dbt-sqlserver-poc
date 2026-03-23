-- az_employees | raw_hr.employees -> Azure Fabric
-- incremental/merge · CDC via _raw_hash · national_id/login/birth_date -> hash SHA2_256 (valores RAW)

{{ config(
    unique_key = 'business_entity_id',
    pre_hook   = "{% if is_incremental() %} DELETE FROM {{ this }} WHERE business_entity_id NOT IN (SELECT business_entity_id FROM {{ ref('stg_hr__employees') }}) {% endif %}"
) }}

WITH source AS (
    SELECT * FROM {{ ref('stg_hr__employees') }}
),

{% if is_incremental() %}
changed AS (
    SELECT s.*
    FROM source             AS s
    LEFT JOIN {{ this }}    AS t  ON s.business_entity_id = t.business_entity_id
    WHERE t.business_entity_id IS NULL
       OR s._raw_hash <> t._raw_hash
),
{% else %}
changed AS (SELECT * FROM source),
{% endif %}

final AS (
    SELECT
        -- Surrogate key (PK para joins en Fabric)
        {{ dbt_utils.generate_surrogate_key(['business_entity_id']) }}  AS employee_sk,

        -- Identificador de negocio
        business_entity_id,

        -- PII hasheado SHA2_256 del valor RAW
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(national_id_number AS NVARCHAR(MAX)), '')), 2) AS national_id_hash,
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(login_id           AS NVARCHAR(MAX)), '')), 2) AS login_id_hash,
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(CONVERT(VARCHAR(10), birth_date, 120) AS NVARCHAR(MAX)), '')), 2) AS birth_date_hash,

        -- Datos laborales (no PII)
        job_title,
        marital_status,
        gender,
        hire_date,
        salaried_flag,
        vacation_hours,
        sick_leave_hours,

        -- Metadata de fuente
        _ingested_at,
        _source_system,
        _source_entity,
        _pipeline_name,
        _batch_id,
        _raw_hash,
        CURRENT_TIMESTAMP                                               AS _dbt_loaded_at

    FROM changed
)

SELECT * FROM final
