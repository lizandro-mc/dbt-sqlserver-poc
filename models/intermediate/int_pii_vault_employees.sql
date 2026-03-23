-- int_pii_vault_employees | RESTRINGIDO — NUNCA SUBIR A AZURE
-- Boveda PII de empleados. Ver doc("int_pii_vault_employees") para guia de uso.

WITH source AS (
    SELECT * FROM {{ ref('stg_hr__employees') }}
)

SELECT
    -- === CLAVES DE VINCULACION (iguales a las que estan en Azure) ===
    {{ dbt_utils.generate_surrogate_key(['business_entity_id']) }}  AS employee_sk,
    business_entity_id,

    -- === PII EN CLARO (SOLO disponible en SQL Server local) ===
    national_id_number,
    login_id,
    birth_date,

    -- === HASHES (para verificacion cruzada con Azure sin exponer PII)
    --     Calculados sobre los valores RAW — identicos a az_employees ===
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(national_id_number AS NVARCHAR(MAX)), '')), 2) AS national_id_hash,
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(login_id           AS NVARCHAR(MAX)), '')), 2) AS login_id_hash,
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(CONVERT(VARCHAR(10), birth_date, 120) AS NVARCHAR(MAX)), '')), 2) AS birth_date_hash,

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
