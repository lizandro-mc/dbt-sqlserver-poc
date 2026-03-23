{% docs col_ingested_at %}
Timestamp UTC en que esta fila fue cargada a la landing zone raw por el pipeline de ingesta.
Trazabilidad de cuándo llegó el dato al sistema, independientemente de cuándo fue creado en la fuente.
{% enddocs %}

{% docs col_source_system %}
Identificador del sistema de origen del dato (ej. `CRM`, `ERP`, `RRHH`).
Útil para trazabilidad en ambientes multi-fuente.
{% enddocs %}

{% docs col_source_entity %}
Nombre de la tabla o entidad específica dentro del sistema fuente (ej. `customers`, `order_headers`).
{% enddocs %}

{% docs col_pipeline_name %}
Nombre del pipeline de ingesta que cargó este registro (ej. `ingest_crm_customers_v1`).
Permite rastrear qué proceso generó el dato en caso de incidentes.
{% enddocs %}

{% docs col_batch_id %}
Identificador del lote de carga. Agrupa todas las filas cargadas en la misma ejecución del pipeline.
Útil para auditoría y para rollback a nivel de lote.
{% enddocs %}

{% docs col_raw_hash %}
Hash SHA2_256 calculado sobre todos los campos de negocio de la fila (excluyendo metadatos).
Se usa como detector de cambios en el patrón CDC: si `_raw_hash` cambia entre cargas,
la fila se considera modificada y se procesa en la capa az_.
Formato: VARCHAR(64) hexadecimal sin prefijo `0x`.
{% enddocs %}

{% docs col_dbt_loaded_at %}
Timestamp generado por dbt (`CURRENT_TIMESTAMP`) en el momento en que este modelo procesó la fila.
Diferente de `_ingested_at` (cuándo llegó al raw) — este marca cuándo fue transformado.
{% enddocs %}

{% docs col_is_deleted %}
Flag de borrado lógico establecido por el pipeline de ingesta.
`0` = registro activo. `1` = registro eliminado en la fuente.
Los modelos de staging filtran con `WHERE _is_deleted = 0` para exponer solo registros activos.
{% enddocs %}

{% docs col_customer_sk %}
Surrogate key del cliente generada con `dbt_utils.generate_surrogate_key(['customer_id'])`.
Es un hash MD5 del `customer_id` en formato hexadecimal.
Esta misma fórmula se aplica tanto en `az_customers` como en `az_addresses` y `az_order_headers`,
lo que permite hacer JOINs directos en Azure Fabric sin lookups adicionales.
{% enddocs %}

{% docs col_employee_sk %}
Surrogate key del empleado generada con `dbt_utils.generate_surrogate_key(['business_entity_id'])`.
Es un hash MD5 del `business_entity_id` en formato hexadecimal.
Se usa en `az_employees` e `int_pii_vault_employees` con la misma fórmula,
permitiendo vincular registros de Azure con la bóveda PII local.
{% enddocs %}

{% docs col_pii_hash_name %}
Hash SHA2_256 del nombre del cliente en claro (`name` de staging, valor RAW sin normalizar).
No reversible. Usar para verificación cruzada con `int_pii_vault_customers.full_name_hash`
sin necesidad de exponer el nombre en Azure.
Algoritmo: `CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ISNULL(CAST(name AS NVARCHAR(MAX)), '')), 2)`
{% enddocs %}

{% docs col_pii_hash_email %}
Hash SHA2_256 del email del cliente en claro (`email_address` de staging, valor RAW).
No reversible. Para verificar si un email específico está en Azure:
```sql
WHERE email_address_hash = CONVERT(VARCHAR(64),
    HASHBYTES('SHA2_256', ISNULL(CAST('x@ejemplo.com' AS NVARCHAR(MAX)), '')), 2)
```
{% enddocs %}

{% docs col_pii_hash_phone %}
Hash SHA2_256 del teléfono del cliente en claro (`phone` de staging, valor RAW).
No reversible. Útil para detectar si un número específico aparece en los datos de Azure.
{% enddocs %}

{% docs col_pii_hash_national_id %}
Hash SHA2_256 del número de identificación nacional del empleado (`national_id_number` de staging, valor RAW).
No reversible. Para verificar si una cédula específica está en Azure:
```sql
WHERE national_id_hash = CONVERT(VARCHAR(64),
    HASHBYTES('SHA2_256', ISNULL(CAST('123456789' AS NVARCHAR(MAX)), '')), 2)
```
{% enddocs %}

{% docs col_pii_hash_login %}
Hash SHA2_256 del login de dominio del empleado (`login_id` de staging, valor RAW).
No reversible. Permite verificar presencia sin exponer credenciales.
{% enddocs %}

{% docs col_pii_hash_birth_date %}
Hash SHA2_256 de la fecha de nacimiento del empleado, formateada como `YYYY-MM-DD` antes de hashear.
Cálculo: `SHA2_256(CONVERT(VARCHAR(10), birth_date, 120))`.
No reversible.
{% enddocs %}

{% docs col_address_hash_line1 %}
Hash SHA2_256 de la primera línea de dirección (`address_line1`, valor RAW de staging).
La dirección física es PII sensible — solo viaja a Azure en forma de hash.
Para recuperar la dirección en claro: consultar `int_pii_vault_customers` (cuando se implemente).
{% enddocs %}

{% docs col_address_hash_line2 %}
Hash SHA2_256 de la segunda línea de dirección (`address_line2`, valor RAW de staging).
Puede ser NULL cuando no existe segunda línea — el hash se calcula sobre cadena vacía en ese caso.
{% enddocs %}
