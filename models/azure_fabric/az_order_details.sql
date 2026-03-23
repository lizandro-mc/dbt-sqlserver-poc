/*
  az_order_details
  ----------------
  Origen : stg_erp__order_details  (raw_erp.order_details)
  Destino: Azure Fabric

  Materializacion: incremental / merge  (unique_key compuesta)
  - CDC via _raw_hash: solo procesa filas nuevas o modificadas.
  - pre_hook: elimina filas que ya no existen en la fuente (clave compuesta).
  Sin PII.
*/

{{ config(
    unique_key          = ['sales_order_id', 'sales_order_detail_id'],
    pre_hook            = "{% if is_incremental() %} DELETE t FROM {{ this }} t WHERE NOT EXISTS (SELECT 1 FROM {{ ref('stg_erp__order_details') }} s WHERE t.sales_order_id = s.sales_order_id AND t.sales_order_detail_id = s.sales_order_detail_id) {% endif %}"
) }}

WITH source AS (
    SELECT * FROM {{ ref('stg_erp__order_details') }}
),

{% if is_incremental() %}
changed AS (
    SELECT s.*
    FROM source             AS s
    LEFT JOIN {{ this }}    AS t
        ON  s.sales_order_id        = t.sales_order_id
        AND s.sales_order_detail_id = t.sales_order_detail_id
    WHERE t.sales_order_id IS NULL
       OR s._raw_hash <> t._raw_hash
),
{% else %}
changed AS (SELECT * FROM source),
{% endif %}

final AS (
    SELECT
        sales_order_id,
        sales_order_detail_id,
        product_id,
        special_offer_id,
        carrier_tracking_number,
        order_qty,
        unit_price,
        unit_price_discount,
        line_total,
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
