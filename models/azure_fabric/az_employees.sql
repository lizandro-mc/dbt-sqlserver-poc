/*
  az_employees
  ------------
  Tabla certificada para subida a Azure Fabric — empleados.

  Origen: int_employees (HR)
  Granularidad: un registro por empleado activo (business_entity_id unico).

  Politica de seguridad aplicada:
  - Campos PII (national_id_number, login_id, birth_date) EXCLUIDOS.
  - Solo se exponen los hashes SHA2_256 de esos campos.
  - Datos laborales no-sensibles incluidos (cargo, fecha contratacion, etc).

  Metadata de fuente incluida para trazabilidad end-to-end en Fabric.
*/

WITH source AS (
    SELECT * FROM {{ ref('int_employees') }}
)

SELECT
    -- Surrogate key (PK — para joins futuros en Fabric)
    employee_sk,

    -- Identificador de negocio
    business_entity_id,

    -- PII hasheado SHA2_256 (nunca los campos en claro)
    national_id_hash,
    login_id_hash,
    birth_date_hash,

    -- Datos laborales (no PII)
    job_title,
    marital_status,
    gender,
    hire_date,
    salaried_flag,
    vacation_hours,
    sick_leave_hours,

    -- Metadata de fuente para trazabilidad
    _ingested_at,
    _source_system,
    _pipeline_name,
    _batch_id,
    _dbt_loaded_at

FROM source
