WITH source AS (
    SELECT * FROM {{ source('raw_erp', 'order_headers') }}
    WHERE _is_deleted = 0
),

renamed AS (
    SELECT
        -- Primary key
        CAST(sales_order_id           AS INT)            AS sales_order_id,

        -- Foreign keys
        CAST(customer_id              AS INT)            AS customer_id,
        CAST(sales_person_id          AS INT)            AS sales_person_id,
        CAST(territory_id             AS INT)            AS territory_id,

        -- Order identifiers
        CAST(revision_number          AS TINYINT)        AS revision_number,
        CAST(sales_order_number       AS VARCHAR(25))    AS sales_order_number,
        CAST(purchase_order_number    AS VARCHAR(25))    AS purchase_order_number,
        CAST(account_number           AS VARCHAR(20))    AS account_number,

        -- Dates
        CONVERT(DATE, order_date)                        AS order_date,
        CONVERT(DATE, due_date)                          AS due_date,
        CONVERT(DATE, ship_date)                         AS ship_date,

        -- Status flags
        CAST(status                   AS TINYINT)        AS status,
        CAST(online_order_flag        AS BIT)            AS online_order_flag,

        -- Financial amounts
        CAST(sub_total                AS DECIMAL(18, 4)) AS sub_total,
        CAST(tax_amt                  AS DECIMAL(18, 4)) AS tax_amt,
        CAST(freight                  AS DECIMAL(18, 4)) AS freight,
        CAST(total_due                AS DECIMAL(18, 4)) AS total_due,

        -- Metadata columns (preservados de la capa raw)
        _ingested_at,
        _source_system,
        _source_entity,
        _pipeline_name,
        _batch_id,
        _raw_hash,
        _is_deleted,

        -- Auditoria dbt
        CURRENT_TIMESTAMP                                AS _dbt_loaded_at

    FROM source
)

SELECT * FROM renamed
