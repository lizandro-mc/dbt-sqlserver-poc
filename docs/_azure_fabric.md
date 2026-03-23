{% docs az_customers %}
**Capa Azure Fabric — Clientes**

Clientes normalizados y certificados para Azure Fabric. Todo campo PII ha sido
sustituido por su hash SHA2_256. Los datos geográficos (domicilio) están en `az_addresses`.

**Fuente:** `stg_crm__customers` (raw_crm.customers)
**Materialización:** incremental / merge — CDC via `_raw_hash`

**Patrón CDC:**
- Clave única de merge: `customer_id`
- Pre-hook: elimina clientes que ya no existen en staging (bajas)
- Solo procesa filas nuevas o con `_raw_hash` diferente al actual

**PII → Hashes SHA2_256:**
- `name` → `full_name_hash`
- `email_address` → `email_address_hash`
- `phone` → `phone_hash`

Hashes calculados sobre valores **RAW de staging** (mismo algoritmo que
`int_pii_vault_customers`) para verificación cruzada exacta.

**Para recuperar PII:** usar `int_pii_vault_customers` en SQL Server local.

**Relaciones en Azure Fabric:**
- `az_addresses.customer_sk` → `az_customers.customer_sk`
- `az_order_headers.customer_sk` → `az_customers.customer_sk`
{% enddocs %}

{% docs az_addresses %}
**Capa Azure Fabric — Direcciones de Clientes**

Direcciones de clientes con PII de domicilio (líneas de dirección) sustituido por
hashes SHA2_256. Conserva datos geográficos no-PII (ciudad, código postal, país).

**Fuente:** `stg_crm__addresses` (raw_crm.addresses)
**Materialización:** incremental / merge — CDC via `_raw_hash`

**Patrón CDC:**
- Clave única de merge: `address_id`
- Pre-hook: elimina direcciones que ya no existen en staging

**PII → Hashes SHA2_256:**
- `address_line1` → `address_line1_hash`
- `address_line2` → `address_line2_hash` (NULL si no hay segunda línea)

**Datos no-PII conservados:** `city`, `postal_code`, `country_region`, `state_province_id`

**Claves de vinculación:**
- `customer_id` (clave de negocio) — FK a `az_customers.customer_id`
- `customer_sk` (surrogate key) — FK directa a `az_customers.customer_sk`

Ambas claves se calculan inline con `generate_surrogate_key(['customer_id'])`,
igual que en `az_customers`, para JOIN directo en Fabric sin lookup.
{% enddocs %}

{% docs az_order_headers %}
**Capa Azure Fabric — Cabeceras de Órdenes de Venta**

Cabeceras de órdenes normalizadas y certificadas para Azure Fabric. Sin PII.
Incluye referencia al cliente vía `customer_sk` para JOIN directo en Fabric.

**Fuente:** `stg_erp__order_headers` (raw_erp.order_headers)
**Materialización:** incremental / merge — CDC via `_raw_hash`

**Patrón CDC:**
- Clave única de merge: `sales_order_id`
- Pre-hook: elimina órdenes que ya no existen en staging

**Claves de vinculación:**
- `customer_id` — clave de negocio, FK a `az_customers`
- `customer_sk` — surrogate key calculada inline: `generate_surrogate_key(['customer_id'])`
  (misma fórmula que `az_customers`) → JOIN directo sin lookup en Fabric

**Sin PII:** `customer_id` es clave entera del sistema, no dato personal.

**Relaciones en Azure Fabric:**
- `az_order_headers.customer_sk` → `az_customers.customer_sk`
- `az_order_details.sales_order_id` → `az_order_headers.sales_order_id`
{% enddocs %}

{% docs az_order_details %}
**Capa Azure Fabric — Detalle de Órdenes de Venta**

Líneas de detalle de órdenes normalizadas y certificadas para Azure Fabric. Sin PII.
Clave compuesta: `(sales_order_id, sales_order_detail_id)`.

**Fuente:** `stg_erp__order_details` (raw_erp.order_details)
**Materialización:** incremental / merge — CDC via `_raw_hash`

**Patrón CDC (clave compuesta):**
- Clave única de merge: `[sales_order_id, sales_order_detail_id]`
- Pre-hook: usa `NOT EXISTS` (dos columnas) para eliminar líneas que ya no existen:
  {% raw %}
  ```sql
  DELETE t FROM {{ this }} t
  WHERE NOT EXISTS (
      SELECT 1 FROM stg WHERE t.sales_order_id = s.sales_order_id
      AND t.sales_order_detail_id = s.sales_order_detail_id
  )
  ```
  {% endraw %}

**Sin PII.**

**Relaciones en Azure Fabric:**
- `az_order_details.sales_order_id` → `az_order_headers.sales_order_id`
- `az_order_details.product_id` → `az_products.product_id`
{% enddocs %}

{% docs az_products %}
**Capa Azure Fabric — Catálogo de Productos**

Catálogo de productos normalizado y certificado para Azure Fabric. Sin PII.
Incluye atributos comerciales, financieros y de inventario.

**Fuente:** `stg_erp__products` (raw_erp.products)
**Materialización:** incremental / merge — CDC via `_raw_hash`

**Patrón CDC:**
- Clave única de merge: `product_id`
- Pre-hook: elimina productos que ya no existen en staging

**Sin PII.**

**Atributos incluidos:** identificadores, precios de lista, costo estándar,
atributos físicos (color, talla, peso), métricas de inventario
(safety_stock_level, reorder_point).
{% enddocs %}

{% docs az_employees %}
**Capa Azure Fabric — Empleados**

Empleados normalizados y certificados para Azure Fabric. Todo campo PII de identidad
sustituido por hash SHA2_256. Datos laborales no-PII conservados en claro.

**Fuente:** `stg_hr__employees` (raw_hr.employees)
**Materialización:** incremental / merge — CDC via `_raw_hash`

**Patrón CDC:**
- Clave única de merge: `business_entity_id`
- Pre-hook: elimina empleados que ya no existen en staging (bajas)

**PII → Hashes SHA2_256:**
- `national_id_number` → `national_id_hash`
- `login_id` → `login_id_hash`
- `birth_date` → `birth_date_hash` (formato `YYYY-MM-DD` antes de hashear)

Hashes calculados sobre valores **RAW de staging** (mismo algoritmo que
`int_pii_vault_employees`) para verificación cruzada exacta.

**Datos laborales conservados (no PII):**
`job_title`, `marital_status`, `gender`, `hire_date`, `salaried_flag`,
`vacation_hours`, `sick_leave_hours`

**Para recuperar PII:** usar `int_pii_vault_employees` en SQL Server local.

**employee_sk:** surrogate key calculada con `generate_surrogate_key(['business_entity_id'])`.
{% enddocs %}

{% docs az_departments %}
**Capa Azure Fabric — Catálogo de Departamentos**

Catálogo de departamentos organizacionales, normalizado y certificado para Azure Fabric.
Tabla de referencia semi-estática. Sin PII.

**Fuente:** `stg_hr__departments` (raw_hr.departments)
**Materialización:** incremental / merge — CDC via `_raw_hash`

**Patrón CDC:**
- Clave única de merge: `department_id`
- Pre-hook: elimina departamentos que ya no existen en staging

**Renombres aplicados:**
- `name` → `department_name` (evita conflicto con palabra reservada SQL)
- `group_name` → `department_group`

**Sin PII.**
{% enddocs %}

{% docs az_orders %}
**Capa Azure Fabric — Órdenes Analíticas (tabla desnormalizada)**

Vista analítica desnormalizada que combina cabecera + detalle de órdenes en
granularidad línea. Útil para reportes y dashboards en Fabric sin JOINs adicionales.

**Fuente:** `int_orders` (intermediate layer — ya tiene el join completo)
**Materialización:** `table` (rebuild completo en cada run, NO incremental)

**Por qué table y no incremental:**
Este modelo es un join analítico de múltiples fuentes. Implementar CDC en un
join de tres tablas añade complejidad sin beneficio proporcional. El rebuild
completo garantiza consistencia.

**Referencia al cliente:**
Solo incluye `customer_sk` (surrogate key, sin PII). `customer_id` no se expone
para reducir la superficie de datos personales indirectos en el join analítico.

**Campos calculados (heredados de int_orders):**
- `line_total_net`: valor neto de línea = `qty * price * (1 - discount)`
- `discount_amount`: monto de descuento = `qty * price * discount`

**Sin PII.** Sin metadatos de fuente (`_source_entity`, `_batch_id`) — es
un modelo derivado, no un espejo directo de una tabla raw.

**Relaciones en Azure Fabric:**
- `az_orders.customer_sk` → `az_customers.customer_sk`
- `az_orders.product_id` → `az_products.product_id`
{% enddocs %}
