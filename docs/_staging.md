{% docs stg_crm__customers %}
**Capa Staging — Clientes CRM**

Normaliza y tipifica los clientes del sistema CRM. Es el punto de entrada oficial
de datos de clientes para todas las capas superiores.

**Transformaciones aplicadas:**
- Cast explícito de tipos (`customer_id → INT`, `name → VARCHAR(200)`, etc.)
- Filtro de borrados lógicos: `WHERE _is_deleted = 0`
- Sin cambios de valores, sin joins — solo normalización estructural

**Contrato de datos:**
- `customer_id`: not_null + unique
- `account_number`, `name`: not_null
- `_ingested_at`, `_dbt_loaded_at`: not_null

**Nota sobre PII:** este modelo expone `name`, `email_address` y `phone` en claro.
Solo debe usarse dentro del servidor SQL local. Las capas az_ hashean estos campos.

**Fuente:** `raw_crm.customers`
{% enddocs %}

{% docs stg_crm__addresses %}
**Capa Staging — Direcciones de Clientes CRM**

Normaliza y tipifica las direcciones del sistema CRM. Un cliente puede tener
múltiples direcciones activas.

**Transformaciones aplicadas:**
- Cast explícito de tipos
- Filtro de borrados lógicos: `WHERE _is_deleted = 0`

**Contrato de datos:**
- `address_id`: not_null + unique
- `customer_id`: not_null + relationship → `stg_crm__customers` (severity: warn)
- `address_line1`, `city`: not_null
- `_ingested_at`, `_dbt_loaded_at`: not_null

**Nota sobre PII:** `address_line1` y `address_line2` son PII (dirección física).
En `az_addresses` estos campos viajan como hashes SHA2_256.

**Fuente:** `raw_crm.addresses`
{% enddocs %}

{% docs stg_erp__order_headers %}
**Capa Staging — Cabeceras de Órdenes ERP**

Normaliza las cabeceras de órdenes de venta del ERP. Cada fila es una orden de venta
con su contexto completo: cliente, fechas, estado y montos financieros totales.

**Transformaciones aplicadas:**
- Cast explícito de tipos (`sales_order_id → INT`, `order_date → DATE`, montos → `DECIMAL(18,4)`)
- Filtro de borrados lógicos: `WHERE _is_deleted = 0`

**Contrato de datos:**
- `sales_order_id`: not_null + unique
- `customer_id`, `order_date`, `status`, `sub_total`, `total_due`: not_null
- `status`: accepted_values [1,2,3,4,5,6] (severity: warn)
- `_ingested_at`, `_dbt_loaded_at`: not_null

**Valores de status:**
`1` In Process · `2` Approved · `3` Backordered · `4` Rejected · `5` Shipped · `6` Cancelled

**Sin PII:** `customer_id` es clave entera de sistema.

**Fuente:** `raw_erp.order_headers`
{% enddocs %}

{% docs stg_erp__order_details %}
**Capa Staging — Detalle de Órdenes ERP**

Normaliza las líneas de detalle de órdenes del ERP. Cada fila es un producto dentro
de una orden de venta (granularidad: línea de orden).

**Transformaciones aplicadas:**
- Cast explícito de tipos (`order_qty → SMALLINT`, precios → `DECIMAL(18,4)`)
- Filtro de borrados lógicos: `WHERE _is_deleted = 0`

**Contrato de datos:**
- Clave compuesta: `dbt_utils.unique_combination_of_columns([sales_order_id, sales_order_detail_id])`
- `sales_order_id`: not_null + relationship → `stg_erp__order_headers` (severity: **error**)
- `product_id`: not_null + relationship → `stg_erp__products` (severity: warn)
- `order_qty`, `unit_price`, `line_total`: not_null
- `_ingested_at`, `_dbt_loaded_at`: not_null

**Sin PII.**

**Fuente:** `raw_erp.order_details`
{% enddocs %}

{% docs stg_erp__products %}
**Capa Staging — Catálogo de Productos ERP**

Normaliza el catálogo de productos del ERP. Incluye identificadores, precios,
costos de producción, atributos físicos y métricas de inventario.

**Transformaciones aplicadas:**
- Cast explícito de tipos
- Filtro de borrados lógicos: `WHERE _is_deleted = 0`

**Contrato de datos:**
- `product_id`: not_null + unique
- `product_number`, `product_name`: not_null
- `_ingested_at`, `_dbt_loaded_at`: not_null

**Sin PII.**

**Freshness relajada:** tabla de catálogo, cambios infrecuentes (warn 7d, error 30d).

**Fuente:** `raw_erp.products`
{% enddocs %}

{% docs stg_hr__employees %}
**Capa Staging — Empleados RRHH**

Normaliza los empleados del sistema de RRHH. Incluye datos de identidad,
laborales y de compensación. **Contiene PII sensible** — acceso restringido.

**Transformaciones aplicadas:**
- Cast explícito de tipos (`business_entity_id → INT`, `birth_date → DATE`, etc.)
- Filtro de borrados lógicos: `WHERE _is_deleted = 0`

**Contrato de datos:**
- `business_entity_id`: not_null + unique
- `national_id_number`, `job_title`, `hire_date`: not_null
- `marital_status`: accepted_values ['M','S'] (severity: warn)
- `gender`: accepted_values ['M','F'] (severity: warn)
- `_ingested_at`, `_dbt_loaded_at`: not_null

**PII presente en esta capa:** `national_id_number`, `login_id`, `birth_date`.
Estos campos NO deben exponerse en capas que van a Azure. Ver `az_employees`
(solo hashes) e `int_pii_vault_employees` (vault local).

**Fuente:** `raw_hr.employees`
{% enddocs %}

{% docs stg_hr__departments %}
**Capa Staging — Catálogo de Departamentos RRHH**

Normaliza el catálogo de departamentos. Tabla de referencia organizacional.
Cada departamento pertenece a un grupo funcional (Engineering, Sales, etc.).

**Transformaciones aplicadas:**
- Cast explícito de tipos
- Filtro de borrados lógicos: `WHERE _is_deleted = 0`

**Contrato de datos:**
- `department_id`: not_null + unique
- `name`, `group_name`: not_null
- `_ingested_at`, `_dbt_loaded_at`: not_null

**Sin PII.**

**Fuente:** `raw_hr.departments`
{% enddocs %}
