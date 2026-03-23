-- az_order_headers | raw_erp.order_headers -> Azure Fabric
-- incremental/merge · CDC via _raw_hash · sin PII · customer_sk inline

{{ config(
    unique_key = 'sales_order_id',
    pre_hook   = "{% if is_incremental() %} DELETE FROM {{ this }} WHERE sales_order_id NOT IN (SELECT sales_order_id FROM {{ ref('stg_erp__order_headers') }}) {% endif %}"
) }}

WITH source AS (
    SELECT * FROM {{ ref('stg_erp__order_headers') }}
),

{% if is_incremental() %}
changed AS (
    SELECT s.*
    FROM source             AS s
    LEFT JOIN {{ this }}    AS t  ON s.sales_order_id = t.sales_order_id
    WHERE t.sales_order_id IS NULL
       OR s._raw_hash <> t._raw_hash
),
{% else %}
changed AS (SELECT * FROM source),
{% endif %}

final AS (
    SELECT
        -- Clave primaria
        sales_order_id,

        -- Claves foraneas
        customer_id,
        {{ dbt_utils.generate_surrogate_key(['customer_id']) }}     AS customer_sk,
        sales_person_id,
        territory_id,

        -- Identificadores de la orden
        revision_number,
        sales_order_number,
        purchase_order_number,
        account_number,

        -- Fechas
        order_date,
        due_date,
        ship_date,

        -- Estado y canal
        status,
        online_order_flag,

        -- Montos financieros
        sub_total,
        tax_amt,
        freight,
        total_due,

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
