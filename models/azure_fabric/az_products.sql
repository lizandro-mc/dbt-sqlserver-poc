-- az_products | raw_erp.products -> Azure Fabric
-- incremental/merge · CDC via _raw_hash · sin PII

{{ config(
    unique_key = 'product_id',
    pre_hook   = "{% if is_incremental() %} DELETE FROM {{ this }} WHERE product_id NOT IN (SELECT product_id FROM {{ ref('stg_erp__products') }}) {% endif %}"
) }}

WITH source AS (
    SELECT * FROM {{ ref('stg_erp__products') }}
),

{% if is_incremental() %}
changed AS (
    SELECT s.*
    FROM source             AS s
    LEFT JOIN {{ this }}    AS t  ON s.product_id = t.product_id
    WHERE t.product_id IS NULL
       OR s._raw_hash <> t._raw_hash
),
{% else %}
changed AS (SELECT * FROM source),
{% endif %}

final AS (
    SELECT
        product_id,
        product_number,
        product_name,
        standard_cost,
        list_price,
        finished_goods_flag,
        color,
        size,
        weight,
        safety_stock_level,
        reorder_point,
        _ingested_at,
        _source_system,
        _source_entity,
        _pipeline_name,
        _batch_id,
        _raw_hash,
        CURRENT_TIMESTAMP   AS _dbt_loaded_at
    FROM changed
)

SELECT * FROM final
