/*
  az_order_headers
  ----------------
  Tabla certificada para subida a Azure Fabric — cabeceras de ordenes de venta.

  Origen: stg_erp__order_headers (ERP)
  Granularidad: un registro por orden de venta (sales_order_id unico).

  Sin datos PII. El customer_id es una clave de negocio (entero, no dato personal).
  Se agrega customer_sk (via int_customers) para facilitar joins en Fabric
  sin necesidad de exponer logica de negocio del CRM.
*/

WITH order_headers AS (
    SELECT * FROM {{ ref('stg_erp__order_headers') }}
),

-- Traer solo la surrogate key del cliente para enriquecer la cabecera
customers AS (
    SELECT
        customer_id,
        customer_sk
    FROM {{ ref('int_customers') }}
)

SELECT
    -- Clave primaria
    h.sales_order_id,

    -- Claves foraneas
    h.customer_id,
    c.customer_sk,              -- Surrogate key para joins en Fabric
    h.sales_person_id,
    h.territory_id,

    -- Identificadores de la orden
    h.revision_number,
    h.sales_order_number,
    h.purchase_order_number,
    h.account_number,

    -- Fechas
    h.order_date,
    h.due_date,
    h.ship_date,

    -- Estado y canal
    h.status,
    h.online_order_flag,

    -- Montos financieros
    h.sub_total,
    h.tax_amt,
    h.freight,
    h.total_due,

    -- Metadata de fuente para trazabilidad
    h._ingested_at,
    h._source_system,
    h._source_entity,
    h._pipeline_name,
    h._batch_id,
    h._raw_hash,
    h._dbt_loaded_at

FROM order_headers AS h
LEFT JOIN customers AS c
    ON h.customer_id = c.customer_id
