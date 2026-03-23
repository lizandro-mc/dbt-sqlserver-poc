WITH source AS (
    SELECT * FROM {{ source('raw_hr', 'departments') }}
    WHERE _is_deleted = 0
),

renamed AS (
    SELECT
        -- Primary key
        CAST(department_id   AS SMALLINT)      AS department_id,

        -- Business attributes
        CAST(name            AS VARCHAR(100))  AS name,
        CAST(group_name      AS VARCHAR(100))  AS group_name,

        -- Metadata columns (preservados de la capa raw)
        _ingested_at,
        _source_system,
        _source_entity,
        _pipeline_name,
        _batch_id,
        _raw_hash,
        _is_deleted,

        -- Auditoria dbt
        CURRENT_TIMESTAMP                      AS _dbt_loaded_at

    FROM source
)

SELECT * FROM renamed
