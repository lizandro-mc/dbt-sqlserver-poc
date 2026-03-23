/*
  az_products
  -----------
  Tabla certificada para subida a Azure Fabric — catalogo de productos.

  Origen: stg_erp__products (ERP)
  Granularidad: un registro por producto (product_id unico).
  Sin datos PII — todos los atributos son datos de negocio.
*/

WITH source AS (
    SELECT * FROM {{ ref('stg_erp__products') }}
)

SELECT
    -- Identificadores
    product_id,
    product_number,

    -- Atributos del producto
    product_name,
    standard_cost,
    list_price,
    finished_goods_flag,
    color,
    size,
    weight,

    -- Inventario
    safety_stock_level,
    reorder_point,

    -- Metadata de fuente para trazabilidad
    _ingested_at,
    _source_system,
    _source_entity,
    _pipeline_name,
    _batch_id,
    _raw_hash,
    _dbt_loaded_at

FROM source
