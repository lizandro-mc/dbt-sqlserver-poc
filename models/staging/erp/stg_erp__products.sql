WITH source AS (
    SELECT * FROM {{ source('raw_erp', 'products') }}
    WHERE _is_deleted = 0
),

renamed AS (
    SELECT
        -- Primary key
        CAST(product_id           AS INT)            AS product_id,

        -- Identifiers
        CAST(product_number       AS VARCHAR(25))    AS product_number,
        CAST(product_name         AS VARCHAR(200))   AS product_name,

        -- Financial
        CAST(standard_cost        AS DECIMAL(18, 4)) AS standard_cost,
        CAST(list_price           AS DECIMAL(18, 4)) AS list_price,

        -- Flags
        CAST(finished_goods_flag  AS BIT)            AS finished_goods_flag,

        -- Physical attributes
        CAST(color                AS VARCHAR(50))    AS color,
        CAST(size                 AS VARCHAR(10))    AS size,
        CAST(weight               AS DECIMAL(8, 2))  AS weight,

        -- Inventory
        CAST(safety_stock_level   AS SMALLINT)       AS safety_stock_level,
        CAST(reorder_point        AS SMALLINT)       AS reorder_point,

        -- Metadata columns (preservados de la capa raw)
        _ingested_at,
        _source_system,
        _source_entity,
        _pipeline_name,
        _batch_id,
        _raw_hash,
        _is_deleted,

        -- Auditoria dbt
        CURRENT_TIMESTAMP                            AS _dbt_loaded_at

    FROM source
)

SELECT * FROM renamed
