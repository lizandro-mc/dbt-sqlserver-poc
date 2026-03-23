/*
  int_pii_vault_customers
  -----------------------
  MODELO LOCAL RESTRINGIDO — NUNCA SUBIR A AZURE NI A FABRIC.

  Registro de vinculacion PII para uso interno exclusivo en SQL Server local.
  Permite recuperar los datos personales de un cliente a partir de cualquier
  clave que se tenga desde la capa Azure Fabric.

  =========================================================
  COMO USAR: recuperar PII desde Azure
  =========================================================

  Caso 1 — tienes el customer_sk (surrogate key de Azure):
    SELECT * FROM intermediate.int_pii_vault_customers
    WHERE customer_sk = '8e4f2a...'

  Caso 2 — tienes el customer_id (clave de negocio):
    SELECT * FROM intermediate.int_pii_vault_customers
    WHERE customer_id = 29825

  Caso 3 — verificar si un email especifico esta en Azure
  (sin exponer el email en la consulta a Azure):
    SELECT * FROM intermediate.int_pii_vault_customers
    WHERE email_address_hash = CONVERT(VARCHAR(64),
        HASHBYTES('SHA2_256', ISNULL(CAST('usuario@ejemplo.com' AS NVARCHAR(MAX)), '')), 2)

  =========================================================
  DIAGRAMA DE VINCULACION
  =========================================================

    Azure Fabric                     SQL Server Local
    ─────────────                    ────────────────
    az_customers                     int_pii_vault_customers
      customer_sk  ──────────────►     customer_sk
      customer_id  ──────────────►     customer_id
      full_name_hash ◄── verifica ──   full_name_hash
                                       full_name          ← PII en claro
                                       email_address      ← PII en claro
                                       phone              ← PII en claro
*/

WITH source AS (
    SELECT * FROM {{ ref('int_customers') }}
)

SELECT
    -- === CLAVES DE VINCULACION (iguales a las que estan en Azure) ===
    customer_sk,
    customer_id,
    account_number,

    -- === PII EN CLARO (SOLO disponible en SQL Server local) ===
    full_name,
    email_address,
    phone,
    address_line1,
    address_line2,

    -- === HASHES (para verificacion cruzada con Azure sin exponer PII) ===
    full_name_hash,
    email_address_hash,
    phone_hash,

    -- === Datos geograficos (non-PII, igual que en Azure) ===
    city,
    state_province_id,
    postal_code,
    country_region,

    -- === Auditoria ===
    _ingested_at,
    _source_system,
    _dbt_loaded_at

FROM source
