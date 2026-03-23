/*
  az_customers
  ------------
  Tabla certificada para subida a Azure Fabric — clientes.

  Origen: int_customers (CRM)
  Granularidad: un registro por cliente activo (customer_id unico).

  Politica de seguridad aplicada:
  - Campos PII (full_name, email_address, phone) EXCLUIDOS.
  - Solo se exponen los hashes SHA2_256 de esos campos.
  - Datos geograficos incluidos (ciudad, pais) — no-PII.

  Metadata de fuente incluida para trazabilidad end-to-end en Fabric.
*/

WITH source AS (
    SELECT * FROM {{ ref('int_customers') }}
)

SELECT
    -- Surrogate key (PK — para joins futuros en Fabric)
    customer_sk,

    -- Identificadores de negocio
    customer_id,
    account_number,
    person_id,
    store_id,
    territory_id,

    -- PII hasheado SHA2_256 (nunca los campos en claro)
    full_name_hash,
    email_address_hash,
    phone_hash,

    -- Datos geograficos (no PII)
    city,
    state_province_id,
    postal_code,
    country_region,

    -- Metadata de fuente para trazabilidad
    _ingested_at,
    _source_system,
    _pipeline_name,
    _batch_id,
    _dbt_loaded_at

FROM source
