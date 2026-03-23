-- int_pii_vault_customers | RESTRINGIDO — NUNCA SUBIR A AZURE
-- Boveda PII de clientes. Ver doc("int_pii_vault_customers") para guia de uso.

WITH source AS (
    SELECT * FROM {{ ref('stg_crm__customers') }}
)

SELECT
    -- === CLAVES DE VINCULACION (iguales a las que estan en Azure) ===
    {{ dbt_utils.generate_surrogate_key(['customer_id']) }}     AS customer_sk,
    customer_id,
    account_number,

    -- === PII EN CLARO (SOLO disponible en SQL Server local) ===
    name,
    email_address,
    phone,

    -- === HASHES (para verificacion cruzada con Azure sin exponer PII)
    --     Calculados sobre los valores RAW — identicos a az_customers ===
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(name          AS NVARCHAR(MAX)), '')), 2) AS full_name_hash,
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(email_address AS NVARCHAR(MAX)), '')), 2) AS email_address_hash,
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(phone         AS NVARCHAR(MAX)), '')), 2) AS phone_hash,

    -- === Auditoria ===
    _ingested_at,
    _source_system,
    _dbt_loaded_at

FROM source
