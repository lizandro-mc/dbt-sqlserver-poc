/*
  az_departments
  --------------
  Tabla certificada para subida a Azure Fabric — catalogo de departamentos.

  Origen: stg_hr__departments (HR)
  Granularidad: un registro por departamento (department_id unico).
  Sin datos PII — datos organizacionales de referencia.
*/

WITH source AS (
    SELECT * FROM {{ ref('stg_hr__departments') }}
)

SELECT
    -- Clave primaria
    department_id,

    -- Atributos del departamento
    name            AS department_name,
    group_name      AS department_group,

    -- Metadata de fuente para trazabilidad
    _ingested_at,
    _source_system,
    _source_entity,
    _pipeline_name,
    _batch_id,
    _raw_hash,
    _dbt_loaded_at

FROM source
