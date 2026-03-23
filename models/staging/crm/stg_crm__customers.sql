WITH source AS (
    SELECT * FROM {{ source('raw_crm', 'customers') }}
    WHERE _is_deleted = 0
),

renamed AS (
    SELECT
        -- Primary key
        CAST(customer_id       AS INT)          AS customer_id,

        -- Foreign keys
        CAST(person_id         AS INT)          AS person_id,
        CAST(store_id          AS INT)          AS store_id,
        CAST(territory_id      AS INT)          AS territory_id,

        -- Business attributes
        CAST(account_number    AS VARCHAR(20))  AS account_number,
        CAST(name              AS VARCHAR(200)) AS name,
        CAST(email_address     AS VARCHAR(150)) AS email_address,
        CAST(phone             AS VARCHAR(30))  AS phone,

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
