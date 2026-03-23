{#
  Macro: get_raw_hash(columns)

  Genera un hash SHA2_256 con HASHBYTES compatible con SQL Server 2016+.
  Devuelve el hash como VARCHAR(64) en hexadecimal (sin el prefijo 0x).

  NOTAS de compatibilidad SQL Server 2016:
    - NO usa CONCAT_WS (disponible desde SQL Server 2017)
    - Usa CONCAT() con separador '|' entre columnas
    - HASHBYTES retorna VARBINARY(32); CONVERT a VARCHAR(64) lo convierte a hex

  Parametros:
    columns  — lista de nombres de columna a incluir en el hash

  Uso en un modelo SQL:
    {{ get_raw_hash(['customer_id', 'name', 'email_address']) }}

  Resultado ejemplo:
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256',
        CONCAT(
            ISNULL(CAST(customer_id AS NVARCHAR(MAX)), ''),
            '|',
            ISNULL(CAST(name AS NVARCHAR(MAX)), ''),
            '|',
            ISNULL(CAST(email_address AS NVARCHAR(MAX)), '')
        )
    ), 2)
#}
{% macro get_raw_hash(columns) %}
    CONVERT(
        VARCHAR(64),
        HASHBYTES(
            'SHA2_256',
            CONCAT(
                {% for col in columns %}
                    ISNULL(CAST({{ col }} AS NVARCHAR(MAX)), '')
                    {%- if not loop.last %}, '|', {% endif %}
                {% endfor %}
            )
        ),
        2
    )
{% endmacro %}
