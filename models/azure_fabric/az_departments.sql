/*
  az_departments
  --------------
  Origen : stg_hr__departments  (raw_hr.departments)
  Destino: Azure Fabric

  Materializacion: incremental / merge
  - CDC via _raw_hash: solo procesa filas nuevas o modificadas.
  - pre_hook: elimina filas que ya no existen en la fuente.
  Sin PII.
*/

{{ config(
    unique_key = 'department_id',
    pre_hook   = "{% if is_incremental() %} DELETE FROM {{ this }} WHERE department_id NOT IN (SELECT department_id FROM {{ ref('stg_hr__departments') }}) {% endif %}"
) }}

WITH source AS (
    SELECT * FROM {{ ref('stg_hr__departments') }}
),

{% if is_incremental() %}
changed AS (
    SELECT s.*
    FROM source             AS s
    LEFT JOIN {{ this }}    AS t  ON s.department_id = t.department_id
    WHERE t.department_id IS NULL
       OR s._raw_hash <> t._raw_hash
),
{% else %}
changed AS (SELECT * FROM source),
{% endif %}

final AS (
    SELECT
        department_id,
        name        AS department_name,
        group_name  AS department_group,
        _ingested_at,
        _source_system,
        _source_entity,
        _pipeline_name,
        _batch_id,
        _raw_hash,
        CURRENT_TIMESTAMP   AS _dbt_loaded_at
    FROM changed
)

SELECT * FROM final
