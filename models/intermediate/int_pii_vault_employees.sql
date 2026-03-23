/*
  int_pii_vault_employees
  -----------------------
  MODELO LOCAL RESTRINGIDO — NUNCA SUBIR A AZURE NI A FABRIC.

  Registro de vinculacion PII para uso interno exclusivo en SQL Server local.
  Permite recuperar los datos personales de un empleado a partir de cualquier
  clave que se tenga desde la capa Azure Fabric.

  =========================================================
  COMO USAR: recuperar PII desde Azure
  =========================================================

  Caso 1 — tienes el employee_sk (surrogate key de Azure):
    SELECT * FROM intermediate.int_pii_vault_employees
    WHERE employee_sk = 'a3c91f...'

  Caso 2 — tienes el business_entity_id (clave de negocio):
    SELECT * FROM intermediate.int_pii_vault_employees
    WHERE business_entity_id = 42

  Caso 3 — verificar si un numero de cedula especifico esta en Azure:
    SELECT * FROM intermediate.int_pii_vault_employees
    WHERE national_id_hash = CONVERT(VARCHAR(64),
        HASHBYTES('SHA2_256', ISNULL(CAST('123456789' AS NVARCHAR(MAX)), '')), 2)

  =========================================================
  DIAGRAMA DE VINCULACION
  =========================================================

    Azure Fabric                     SQL Server Local
    ─────────────                    ────────────────
    az_employees                     int_pii_vault_employees
      employee_sk    ─────────────►    employee_sk
      business_entity_id ─────────►   business_entity_id
      national_id_hash ◄─ verifica ─  national_id_hash
      birth_date_hash  ◄─ verifica ─  birth_date_hash
                                       national_id_number ← PII en claro
                                       login_id           ← PII en claro
                                       birth_date         ← PII en claro
*/

WITH source AS (
    SELECT * FROM {{ ref('int_employees') }}
)

SELECT
    -- === CLAVES DE VINCULACION (iguales a las que estan en Azure) ===
    employee_sk,
    business_entity_id,

    -- === PII EN CLARO (SOLO disponible en SQL Server local) ===
    national_id_number,
    login_id,
    birth_date,

    -- === HASHES (para verificacion cruzada con Azure sin exponer PII) ===
    national_id_hash,
    login_id_hash,
    birth_date_hash,

    -- === Datos laborales (non-PII, igual que en Azure) ===
    job_title,
    marital_status,
    gender,
    hire_date,
    salaried_flag,
    vacation_hours,
    sick_leave_hours,

    -- === Auditoria ===
    _ingested_at,
    _source_system,
    _dbt_loaded_at

FROM source
