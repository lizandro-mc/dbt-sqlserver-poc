{#
  Macro: hash_pii(column)

  Genera un hash SHA2_256 de un campo PII individual.
  Devuelve VARCHAR(64) en hexadecimal (sin prefijo 0x).

  Compatible con SQL Server 2016+.

  Parametros:
    column — nombre de la columna a hashear (puede incluir alias de tabla, e.g. 'e.email')

  Uso:
    {{ hash_pii('email_address') }}     → hash del email
    {{ hash_pii('national_id_number') }} → hash del ID nacional

  Resultado ejemplo:
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(email_address AS NVARCHAR(MAX)), '')), 2)
#}
{% macro hash_pii(column) %}
    CONVERT(
        VARCHAR(64),
        HASHBYTES(
            'SHA2_256',
            ISNULL(CAST({{ column }} AS NVARCHAR(MAX)), '')
        ),
        2
    )
{% endmacro %}
