-- az_addresses | raw_crm.addresses -> Azure Fabric
-- incremental/merge · CDC via _raw_hash · address_line1/2 -> hash SHA2_256 (valores RAW)

{{ config(
    unique_key = 'address_id',
    pre_hook   = "{% if is_incremental() %} DELETE FROM {{ this }} WHERE address_id NOT IN (SELECT address_id FROM {{ ref('stg_crm__addresses') }}) {% endif %}"
) }}

WITH source AS (
    SELECT * FROM {{ ref('stg_crm__addresses') }}
),

{% if is_incremental() %}
changed AS (
    SELECT s.*
    FROM source             AS s
    LEFT JOIN {{ this }}    AS t  ON s.address_id = t.address_id
    WHERE t.address_id IS NULL
       OR s._raw_hash <> t._raw_hash
),
{% else %}
changed AS (SELECT * FROM source),
{% endif %}

final AS (
    SELECT
        -- Clave primaria
        address_id,

        -- Claves de vinculacion con az_customers
        customer_id,
        {{ dbt_utils.generate_surrogate_key(['customer_id']) }}     AS customer_sk,
        state_province_id,

        -- PII hasheado SHA2_256 del valor RAW (direccion fisica)
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(address_line1 AS NVARCHAR(MAX)), '')), 2) AS address_line1_hash,
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(address_line2 AS NVARCHAR(MAX)), '')), 2) AS address_line2_hash,

        -- Datos geograficos (no PII)
        city,
        postal_code,
        country_region,

        -- Metadata de fuente
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
