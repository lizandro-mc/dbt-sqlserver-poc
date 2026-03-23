/*
  az_order_details
  ----------------
  Tabla certificada para subida a Azure Fabric — lineas de detalle de ordenes.

  Origen: stg_erp__order_details (ERP)
  Granularidad: una fila por linea de orden (sales_order_id + sales_order_detail_id).

  Sin datos PII. Referencia a sales_order_id (FK a az_order_headers)
  y product_id (FK a az_products).
*/

WITH source AS (
    SELECT * FROM {{ ref('stg_erp__order_details') }}
)

SELECT
    -- Clave compuesta (PK de la linea)
    sales_order_id,
    sales_order_detail_id,

    -- Claves foraneas
    product_id,
    special_offer_id,

    -- Logistica
    carrier_tracking_number,

    -- Cantidades y precios
    order_qty,
    unit_price,
    unit_price_discount,
    line_total,

    -- Metadata de fuente para trazabilidad
    _ingested_at,
    _source_system,
    _source_entity,
    _pipeline_name,
    _batch_id,
    _raw_hash,
    _dbt_loaded_at

FROM source
