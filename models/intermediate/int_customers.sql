/*
  int_customers
  -------------
  Capa Intermedia de clientes — enriquecimiento + seguridad PII.

  Logica aplicada:
  - Une stg_crm__customers con stg_crm__addresses para enriquecer con datos geograficos.
  - Limpia nombre (UPPER + LTRIM/RTRIM) y email (LOWER + LTRIM/RTRIM).
  - Desduplicacion via ROW_NUMBER(): por customer_id, queda la version mas reciente
    segun _ingested_at.
  - Genera surrogate key con dbt_utils.generate_surrogate_key.
  - Hashea campos PII (full_name, email_address, phone) con SHA2_256 para
    transmision segura hacia la capa Azure Fabric.
  - Compatible con SQL Server 2016+ (sin TRIM, sin STRING_AGG, sin CONCAT_WS).
*/

WITH customers_raw AS (
    SELECT * FROM {{ ref('stg_crm__customers') }}
),

addresses_raw AS (
    SELECT * FROM {{ ref('stg_crm__addresses') }}
),

-- Tomar la direccion principal por cliente (la mas reciente si hay multiples)
addresses_deduped AS (
    SELECT
        customer_id,
        address_line1,
        address_line2,
        city,
        state_province_id,
        postal_code,
        country_region,
        _ingested_at,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY _ingested_at DESC
        ) AS _rn
    FROM addresses_raw
),

addresses AS (
    SELECT * FROM addresses_deduped WHERE _rn = 1
),

-- Unir clientes con su direccion y limpiar campos
customers_enriched AS (
    SELECT
        c.customer_id,
        c.person_id,
        c.store_id,
        c.territory_id,
        c.account_number,

        -- Limpieza de nombre: UPPER + trim compatible con SQL Server 2016
        UPPER(LTRIM(RTRIM(c.name)))                         AS full_name,

        -- Limpieza de email: LOWER + trim
        LOWER(LTRIM(RTRIM(c.email_address)))                AS email_address,

        c.phone,

        -- Datos geograficos de la direccion principal
        a.address_line1,
        a.address_line2,
        a.city,
        a.state_province_id,
        a.postal_code,
        a.country_region,

        -- Auditoria
        c._ingested_at,
        c._source_system,
        c._pipeline_name,
        c._batch_id,

        -- Dedup: cuando hay duplicados de customer_id, quedarse con el mas reciente
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_id
            ORDER BY c._ingested_at DESC
        ) AS _rn

    FROM customers_raw      AS c
    LEFT JOIN addresses     AS a
        ON c.customer_id = a.customer_id
),

deduped AS (
    SELECT * FROM customers_enriched WHERE _rn = 1
),

final AS (
    SELECT
        -- Surrogate key — combinacion de atributos de negocio
        {{ dbt_utils.generate_surrogate_key(['customer_id']) }}
                                                            AS customer_sk,

        customer_id,
        person_id,
        store_id,
        territory_id,
        account_number,

        -- Campos PII en claro (uso interno — NO exponer en Azure Fabric)
        full_name,
        email_address,
        phone,

        -- Campos PII hasheados SHA2_256 (uso en capas publicas / cloud)
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(full_name      AS NVARCHAR(MAX)), '')), 2) AS full_name_hash,
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(email_address  AS NVARCHAR(MAX)), '')), 2) AS email_address_hash,
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(phone          AS NVARCHAR(MAX)), '')), 2) AS phone_hash,

        -- Datos geograficos (no PII)
        address_line1,
        address_line2,
        city,
        state_province_id,
        postal_code,
        country_region,

        -- Auditoria
        _ingested_at,
        _source_system,
        _pipeline_name,
        _batch_id,
        CURRENT_TIMESTAMP                                   AS _dbt_loaded_at

    FROM deduped
)

SELECT * FROM final
