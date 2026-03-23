-- az_orders | int_orders -> Azure Fabric
-- Ordenes analiticas desnormalizadas (table, full rebuild). Sin PII. Ver doc("az_orders").

WITH source AS (
    SELECT * FROM {{ ref('int_orders') }}
)

SELECT
    -- Claves de orden
    sales_order_id,
    sales_order_detail_id,
    sales_order_number,

    -- Referencia al cliente (surrogate key — nunca el customer_id ni PII)
    customer_sk,

    -- Fechas de la orden
    order_date,
    due_date,
    ship_date,

    -- Estado y canal
    status,
    online_order_flag,

    -- Producto
    product_id,

    -- Cantidades y precios
    order_qty,
    unit_price,
    unit_price_discount,
    line_total,
    line_total_net,
    discount_amount,

    -- Totales de cabecera
    sub_total,
    total_due,

    -- Metadata de fuente para trazabilidad
    _ingested_at,
    _source_system,
    _pipeline_name,
    _batch_id,
    _dbt_loaded_at

FROM source
