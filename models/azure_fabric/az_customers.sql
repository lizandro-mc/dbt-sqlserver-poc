-- az_customers | raw_crm.customers -> Azure Fabric
-- incremental/merge · CDC via _raw_hash · name/email/phone -> hash SHA2_256 (valores RAW)

{{ config(
    unique_key = 'customer_id',
    pre_hook   = "{% if is_incremental() %} DELETE FROM {{ this }} WHERE customer_id NOT IN (SELECT customer_id FROM {{ ref('stg_crm__customers') }}) {% endif %}"
) }}

WITH source AS (
    SELECT * FROM {{ ref('stg_crm__customers') }}
),

-- CDC: descartar filas sin cambios para no reprocesar lo que ya esta igual
{% if is_incremental() %}
changed AS (
    SELECT s.*
    FROM source                  AS s
    LEFT JOIN {{ this }}         AS t  ON s.customer_id = t.customer_id
    WHERE t.customer_id IS NULL          -- fila nueva
       OR s._raw_hash <> t._raw_hash     -- fila modificada
),
{% else %}
changed AS (SELECT * FROM source),
{% endif %}

final AS (
    SELECT
        -- Surrogate key (PK para joins en Fabric)
        {{ dbt_utils.generate_surrogate_key(['customer_id']) }}     AS customer_sk,

        -- Identificadores de negocio
        customer_id,
        person_id,
        store_id,
        territory_id,
        account_number,

        -- PII hasheado SHA2_256 del valor RAW (sin normalizacion)
        -- Mismo algoritmo que int_pii_vault_customers -> verificacion cruzada funciona
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(name          AS NVARCHAR(MAX)), '')), 2) AS full_name_hash,
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(email_address AS NVARCHAR(MAX)), '')), 2) AS email_address_hash,
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(phone         AS NVARCHAR(MAX)), '')), 2) AS phone_hash,

        -- Metadata de fuente para trazabilidad
        _ingested_at,
        _source_system,
        _source_entity,
        _pipeline_name,
        _batch_id,
        _raw_hash,
        CURRENT_TIMESTAMP                                           AS _dbt_loaded_at

    FROM changed
)

SELECT * FROM final
