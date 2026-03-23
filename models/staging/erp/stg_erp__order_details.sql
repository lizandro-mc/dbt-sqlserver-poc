WITH source AS (
    SELECT * FROM {{ source('raw_erp', 'order_details') }}
    WHERE _is_deleted = 0
),

renamed AS (
    SELECT
        -- Composite key
        CAST(sales_order_id            AS INT)            AS sales_order_id,
        CAST(sales_order_detail_id     AS INT)            AS sales_order_detail_id,

        -- Foreign keys
        CAST(product_id                AS INT)            AS product_id,
        CAST(special_offer_id          AS INT)            AS special_offer_id,

        -- Logistics
        CAST(carrier_tracking_number   AS VARCHAR(50))    AS carrier_tracking_number,

        -- Quantities and pricing
        CAST(order_qty                 AS SMALLINT)       AS order_qty,
        CAST(unit_price                AS DECIMAL(18, 4)) AS unit_price,
        CAST(unit_price_discount       AS DECIMAL(6, 4))  AS unit_price_discount,
        CAST(line_total                AS DECIMAL(18, 4)) AS line_total,

        -- Metadata columns (preservados de la capa raw)
        _ingested_at,
        _source_system,
        _source_entity,
        _pipeline_name,
        _batch_id,
        _raw_hash,
        _is_deleted,

        -- Auditoria dbt
        CURRENT_TIMESTAMP                                 AS _dbt_loaded_at

    FROM source
)

SELECT * FROM renamed
