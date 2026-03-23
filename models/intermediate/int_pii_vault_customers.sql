/*
  int_pii_vault_customers
  -----------------------
  MODELO LOCAL RESTRINGIDO — NUNCA SUBIR A AZURE NI A FABRIC.

  Registro de vinculacion PII para uso interno exclusivo en SQL Server local.
  Permite recuperar los datos personales de un cliente a partir de cualquier
  clave que se tenga desde la capa Azure Fabric.

  Fuente: stg_crm__customers (valores RAW — mismos que az_customers usa para
  calcular los hashes). Los hashes aqui son identicos a los de az_customers.

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
      full_name_hash ◄── verifica ──   full_name_hash (hash del mismo valor RAW)
      email_address_hash ◄─ verif ──   email_address_hash
                                       name               ← PII en claro
                                       email_address      ← PII en claro
                                       phone              ← PII en claro
*/

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
