-- int_orders | stg_erp__order_headers + stg_erp__order_details + int_customers -> intermediate
-- Ordenes completas (cabecera + detalle) con campos calculados y customer_sk. Ver doc("int_orders").

WITH order_headers AS (
    SELECT * FROM {{ ref('stg_erp__order_headers') }}
),

order_details AS (
    SELECT * FROM {{ ref('stg_erp__order_details') }}
),

customers AS (
    SELECT
        customer_id,
        customer_sk
    FROM {{ ref('int_customers') }}
),

-- Union cabecera + detalle
orders_joined AS (
    SELECT
        -- Claves de orden
        h.sales_order_id,
        d.sales_order_detail_id,

        -- FK a dimension de cliente (surrogate key)
        c.customer_sk,
        h.customer_id,

        -- Atributos de cabecera
        h.order_date,
        h.due_date,
        h.ship_date,
        h.status,
        h.online_order_flag,
        h.sales_order_number,

        -- Atributos de linea
        d.product_id,
        d.order_qty,
        d.unit_price,
        d.unit_price_discount,
        d.line_total,

        -- Campos calculados
        CAST(d.order_qty AS DECIMAL(18, 2))
            * CAST(d.unit_price AS DECIMAL(18, 4))
            * (1 - CAST(d.unit_price_discount AS DECIMAL(6, 4)))    AS line_total_net,

        CAST(d.order_qty AS DECIMAL(18, 2))
            * CAST(d.unit_price AS DECIMAL(18, 4))
            * CAST(d.unit_price_discount AS DECIMAL(6, 4))          AS discount_amount,

        -- Totales de cabecera (para contexto en analisis de linea)
        h.sub_total,
        h.total_due,

        -- Auditoria (cabecera como fuente principal)
        h._ingested_at,
        h._source_system,
        h._pipeline_name,
        h._batch_id,
        CURRENT_TIMESTAMP                                           AS _dbt_loaded_at

    FROM order_headers  AS h
    INNER JOIN order_details AS d
        ON h.sales_order_id = d.sales_order_id
    LEFT JOIN customers  AS c
        ON h.customer_id = c.customer_id
)

SELECT * FROM orders_joined
