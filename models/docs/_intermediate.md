{% docs int_customers %}
**Capa Intermedia — Clientes enriquecidos**

Une datos de clientes y direcciones del CRM, deduplica por `customer_id`,
genera la surrogate key y hashea los campos PII para uso analítico interno.

**Fuentes:** `stg_crm__customers` + `stg_crm__addresses` (LEFT JOIN por `customer_id`)

**Transformaciones:**
- Deduplicación con `ROW_NUMBER()` por `customer_id` (más reciente por `_ingested_at`)
- Surrogate key: `generate_surrogate_key(['customer_id'])` → `customer_sk`
- Limpieza de nombre: `UPPER(LTRIM(RTRIM(name)))` → `full_name`
- Limpieza de email: `LOWER(LTRIM(RTRIM(email_address)))` → `email_address`
- Hash PII sobre **valores normalizados** (distinto de az_ que usa valores raw)

**Nota importante sobre hashes:**
Los hashes en `int_customers` se calculan sobre valores *normalizados*
(UPPER/LOWER aplicados). Son para uso analítico interno. Los hashes de `az_customers`
e `int_pii_vault_customers` se calculan sobre valores raw para permitir verificación
cruzada. **No comparar hashes entre int_customers y az_customers.**

**Uso:** este modelo alimenta `int_orders` (para obtener `customer_sk` en órdenes).
{% enddocs %}

{% docs int_employees %}
**Capa Intermedia — Empleados con surrogate key y PII hasheado**

Deduplica empleados por `business_entity_id`, genera la surrogate key y hashea
los campos PII para uso analítico interno.

**Fuente:** `stg_hr__employees`

**Transformaciones:**
- Deduplicación con `ROW_NUMBER()` por `business_entity_id` (más reciente por `_ingested_at`)
- Surrogate key: `generate_surrogate_key(['business_entity_id'])` → `employee_sk`
- Hash PII: `national_id_number`, `login_id`, `birth_date` → SHA2_256

**Datos PII en claro:** `national_id_number`, `login_id`, `birth_date` permanecen
accesibles en este modelo para uso analítico interno en SQL Server.
Para uso en Azure: ver `az_employees` (solo hashes).
Para recuperar PII desde claves de Azure: ver `int_pii_vault_employees`.
{% enddocs %}

{% docs int_orders %}
**Capa Intermedia — Órdenes de venta completas**

Construye la vista completa de una línea de orden uniendo cabecera + detalle +
referencia al cliente. Incluye campos calculados de valor financiero.

**Fuentes:**
- `stg_erp__order_headers` + `stg_erp__order_details` (INNER JOIN por `sales_order_id`)
- `int_customers` (LEFT JOIN por `customer_id` para traer `customer_sk`)

**Campos calculados:**
- `line_total_net`: `order_qty * unit_price * (1 - unit_price_discount)` — valor neto de línea
- `discount_amount`: `order_qty * unit_price * unit_price_discount` — monto de descuento aplicado

**Granularidad:** un registro por línea de orden (`sales_order_id` + `sales_order_detail_id`).

**Nota sobre customer_sk:** se obtiene de `int_customers` para consistencia con
el surrogate key usado en `az_customers`. Si un `customer_id` no existe en
`int_customers` (caso borde), `customer_sk` será NULL.

**Alimenta:** `az_orders` (capa Azure Fabric, tabla analítica).
{% enddocs %}

{% docs int_pii_vault_customers %}
**Bóveda PII de Clientes — MODELO LOCAL RESTRINGIDO**

> ⚠️ **NUNCA subir a Azure ni a Fabric. Solo SQL Server local.**
> Tags: `pii_vault`, `restricted`, `local_only`

Registra la vinculación entre las claves de Azure Fabric (`customer_sk`, `customer_id`)
y los datos personales en claro de cada cliente. Permite recuperar PII de forma
controlada dado cualquier identificador que llegue desde Azure.

**Fuente:** `stg_crm__customers` (valores RAW — sin normalización)

**Por qué valores RAW:**
Los hashes en este modelo se calculan sobre los mismos valores raw que usa `az_customers`.
Esto garantiza que `int_pii_vault_customers.full_name_hash == az_customers.full_name_hash`
para el mismo cliente, permitiendo verificación cruzada exacta.

**Casos de uso:**

*Caso 1 — tienes el customer_sk de Azure:*
```sql
SELECT name, email_address, phone
FROM intermediate.int_pii_vault_customers
WHERE customer_sk = '<valor de az_customers.customer_sk>'
```

*Caso 2 — tienes el customer_id:*
```sql
SELECT name, email_address, phone
FROM intermediate.int_pii_vault_customers
WHERE customer_id = 29825
```

*Caso 3 — verificar si un email específico aparece en Azure (sin exponer el email):*
```sql
SELECT customer_sk, customer_id
FROM intermediate.int_pii_vault_customers
WHERE email_address_hash = CONVERT(VARCHAR(64),
    HASHBYTES('SHA2_256', ISNULL(CAST('usuario@dominio.com' AS NVARCHAR(MAX)), '')), 2)
```

**Campos expuestos:**
- `customer_sk` / `customer_id` / `account_number` — claves de vinculación
- `name` / `email_address` / `phone` — PII en claro (SOLO local)
- `full_name_hash` / `email_address_hash` / `phone_hash` — para verificación cruzada

**Nota:** las direcciones físicas se almacenan en `az_addresses` (hashes) pero
aún no existe una bóveda dedicada para ellas. En el proyecto real, implementar
`int_pii_vault_addresses` con `address_line1` y `address_line2` en claro.
{% enddocs %}

{% docs int_pii_vault_employees %}
**Bóveda PII de Empleados — MODELO LOCAL RESTRINGIDO**

> ⚠️ **NUNCA subir a Azure ni a Fabric. Solo SQL Server local.**
> Tags: `pii_vault`, `restricted`, `local_only`

Registra la vinculación entre las claves de Azure Fabric (`employee_sk`, `business_entity_id`)
y los datos personales en claro de cada empleado.

**Fuente:** `stg_hr__employees` (valores RAW — sin normalización)

**Por qué valores RAW:**
Los hashes se calculan sobre los mismos valores raw que usa `az_employees`.
`int_pii_vault_employees.national_id_hash == az_employees.national_id_hash`
para el mismo empleado — verificación cruzada exacta garantizada.

**Casos de uso:**

*Caso 1 — tienes el employee_sk de Azure:*
```sql
SELECT national_id_number, login_id, birth_date
FROM intermediate.int_pii_vault_employees
WHERE employee_sk = '<valor de az_employees.employee_sk>'
```

*Caso 2 — tienes el business_entity_id:*
```sql
SELECT national_id_number, login_id, birth_date
FROM intermediate.int_pii_vault_employees
WHERE business_entity_id = 42
```

*Caso 3 — verificar si una cédula específica está en Azure:*
```sql
SELECT employee_sk, business_entity_id
FROM intermediate.int_pii_vault_employees
WHERE national_id_hash = CONVERT(VARCHAR(64),
    HASHBYTES('SHA2_256', ISNULL(CAST('123456789' AS NVARCHAR(MAX)), '')), 2)
```

**Campos expuestos:**
- `employee_sk` / `business_entity_id` — claves de vinculación
- `national_id_number` / `login_id` / `birth_date` — PII en claro (SOLO local)
- `national_id_hash` / `login_id_hash` / `birth_date_hash` — para verificación cruzada
- Campos laborales no-PII: `job_title`, `gender`, `hire_date`, `salaried_flag`, etc.
{% enddocs %}
