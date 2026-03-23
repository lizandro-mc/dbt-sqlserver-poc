/*
  int_employees
  -------------
  Capa Intermedia de empleados — enriquecimiento + seguridad PII.

  Logica aplicada:
  - Toma stg_hr__employees como base.
  - Desduplicacion via ROW_NUMBER(): por business_entity_id, version mas reciente.
  - Genera surrogate key con dbt_utils.generate_surrogate_key.
  - Hashea campos PII sensibles (national_id_number, birth_date, login_id) con SHA2_256
    para transmision segura hacia la capa Azure Fabric.
  - Compatible con SQL Server 2016+.
*/

WITH employees_raw AS (
    SELECT * FROM {{ ref('stg_hr__employees') }}
),

-- Deduplicacion: quedar con la version mas reciente por empleado
employees_deduped AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY business_entity_id
            ORDER BY _ingested_at DESC
        ) AS _rn
    FROM employees_raw
),

final AS (
    SELECT
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['business_entity_id']) }}
                                                                    AS employee_sk,

        business_entity_id,

        -- Campos PII en claro (uso interno — NO exponer en Azure Fabric)
        national_id_number,
        login_id,
        birth_date,

        -- Campos PII hasheados SHA2_256 (uso en capas publicas / cloud)
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(national_id_number  AS NVARCHAR(MAX)), '')), 2) AS national_id_hash,
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(login_id            AS NVARCHAR(MAX)), '')), 2) AS login_id_hash,
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(CONVERT(VARCHAR(10), birth_date, 120) AS NVARCHAR(MAX)), '')), 2) AS birth_date_hash,

        -- Informacion laboral (no PII)
        job_title,
        marital_status,
        gender,
        hire_date,
        salaried_flag,
        vacation_hours,
        sick_leave_hours,

        -- Auditoria
        _ingested_at,
        _source_system,
        _pipeline_name,
        _batch_id,
        CURRENT_TIMESTAMP                                           AS _dbt_loaded_at

    FROM employees_deduped
    WHERE _rn = 1
)

SELECT * FROM final
