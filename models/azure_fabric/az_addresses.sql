/*
  az_addresses
  ------------
  Tabla certificada para subida a Azure Fabric — direcciones de clientes.

  Origen: stg_crm__addresses (CRM)
  Granularidad: un registro por direccion activa (address_id unico).

  Politica de seguridad:
  - address_line1 y address_line2 son PII (direccion fisica residencial).
  - Se exponen hasheadas SHA2_256.
  - city, postal_code, country_region son datos geograficos no-PII.

  Vinculacion con az_customers:
  - customer_id  — clave de negocio (FK a az_customers.customer_id)
  - customer_sk  — surrogate key (FK a az_customers.customer_sk)
    Calculada con la misma formula que en int_customers para garantizar
    consistencia de join en Fabric sin necesidad de lookup adicional.
*/

WITH source AS (
    SELECT * FROM {{ ref('stg_crm__addresses') }}
)

SELECT
    -- Clave primaria
    address_id,

    -- Claves de vinculacion con az_customers
    customer_id,
    {{ dbt_utils.generate_surrogate_key(['customer_id']) }} AS customer_sk,

    state_province_id,

    -- PII hasheado SHA2_256 (direccion fisica)
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(address_line1 AS NVARCHAR(MAX)), '')), 2) AS address_line1_hash,
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(address_line2 AS NVARCHAR(MAX)), '')), 2) AS address_line2_hash,

    -- Datos geograficos (no PII)
    city,
    postal_code,
    country_region,

    -- Metadata de fuente para trazabilidad
    _ingested_at,
    _source_system,
    _source_entity,
    _pipeline_name,
    _batch_id,
    _raw_hash,
    _dbt_loaded_at

FROM source
