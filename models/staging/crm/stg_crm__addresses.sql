WITH source AS (
    SELECT * FROM {{ source('raw_crm', 'addresses') }}
    WHERE _is_deleted = 0
),

renamed AS (
    SELECT
        -- Primary key
        CAST(address_id        AS INT)          AS address_id,

        -- Foreign keys
        CAST(customer_id       AS INT)          AS customer_id,
        CAST(state_province_id AS INT)          AS state_province_id,

        -- Business attributes
        CAST(address_line1     AS VARCHAR(200)) AS address_line1,
        CAST(address_line2     AS VARCHAR(200)) AS address_line2,
        CAST(city              AS VARCHAR(100)) AS city,
        CAST(postal_code       AS VARCHAR(20))  AS postal_code,
        CAST(country_region    AS VARCHAR(100)) AS country_region,

        -- Metadata columns (preservados de la capa raw)
        _ingested_at,
        _source_system,
        _source_entity,
        _pipeline_name,
        _batch_id,
        _raw_hash,
        _is_deleted,

        -- Auditoria dbt
        CURRENT_TIMESTAMP                       AS _dbt_loaded_at

    FROM source
)

SELECT * FROM renamed
