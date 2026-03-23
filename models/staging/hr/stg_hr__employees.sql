WITH source AS (
    SELECT * FROM {{ source('raw_hr', 'employees') }}
    WHERE _is_deleted = 0
),

renamed AS (
    SELECT
        -- Primary key
        CAST(business_entity_id  AS INT)          AS business_entity_id,

        -- Identifiers
        CAST(national_id_number  AS VARCHAR(25))  AS national_id_number,
        CAST(login_id            AS VARCHAR(100)) AS login_id,

        -- Personal information
        CAST(job_title           AS VARCHAR(100)) AS job_title,
        CONVERT(DATE, birth_date)                 AS birth_date,
        CAST(marital_status      AS CHAR(1))      AS marital_status,
        CAST(gender              AS CHAR(1))      AS gender,

        -- Employment information
        CONVERT(DATE, hire_date)                  AS hire_date,
        CAST(salaried_flag       AS BIT)          AS salaried_flag,
        CAST(vacation_hours      AS SMALLINT)     AS vacation_hours,
        CAST(sick_leave_hours    AS SMALLINT)     AS sick_leave_hours,

        -- Metadata columns (preservados de la capa raw)
        _ingested_at,
        _source_system,
        _source_entity,
        _pipeline_name,
        _batch_id,
        _raw_hash,
        _is_deleted,

        -- Auditoria dbt
        CURRENT_TIMESTAMP                         AS _dbt_loaded_at

    FROM source
)

SELECT * FROM renamed
