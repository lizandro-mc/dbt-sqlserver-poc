# Handoff: dbt-sqlserver-poc → dbt-fabric

Este documento describe el contrato de entrega entre el proyecto **dbt-sqlserver-poc** (SQL Server local) y el proyecto **dbt-fabric** (Microsoft Fabric). Sirve como contexto completo para que el proyecto Fabric sea diseñado sabiendo exactamente qué datos recibe, en qué formato, con qué garantías y con qué restricciones.

---

## Qué es este proyecto y qué produce

**dbt-sqlserver-poc** es el pipeline de transformación local que:

1. Lee datos de sistemas operacionales simulados (CRM, ERP, RRHH) desde la landing zone `dbt_cibao_raw`
2. Los normaliza, deduplica, enriquece y hashea campos PII
3. Produce la capa `db_cibao_dev.azure_fabric.*` — tablas certificadas, sin PII en claro, listas para subir a Microsoft Fabric

**La capa `azure_fabric.*` es la fuente de datos del proyecto dbt-fabric.**

---

## Restricción fundamental: PII

> **Ningún dato personal viaja a Fabric en claro. Solo hashes SHA2-256.**

En Fabric no existirá nunca: nombres, emails, teléfonos, cédulas, fechas de nacimiento ni direcciones en texto.

Lo que existe en Fabric son hashes determinísticos:

| Campo original | Hash en Fabric | Tabla |
| --- | --- | --- |
| `name` | `full_name_hash` | az_customers |
| `email_address` | `email_address_hash` | az_customers |
| `phone` | `phone_hash` | az_customers |
| `address_line1` | `address_line1_hash` | az_addresses |
| `address_line2` | `address_line2_hash` | az_addresses |
| `national_id_number` | `national_id_hash` | az_employees |
| `login_id` | `login_id_hash` | az_employees |
| `birth_date` | `birth_date_hash` | az_employees |

Los hashes son **SHA2-256 sobre el valor raw de staging** (sin normalización previa). Esto garantiza que el mismo valor produce el mismo hash en SQL Server y en Fabric, permitiendo verificación cruzada desde ambos lados sin exponer el dato.

Para recuperar PII dado un identificador de Fabric, la operación se realiza en SQL Server local contra los modelos `int_pii_vault_*`. Esos modelos nunca se despliegan en Fabric.

---

## Tablas que llegan a Fabric

Son 8 tablas, todas en el schema `azure_fabric` de `db_cibao_dev`:

### az_customers

Clientes del CRM. Una fila por cliente activo.

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `customer_sk` | VARCHAR(64) | Surrogate key — PK en Fabric |
| `customer_id` | INT | PK natural del CRM |
| `account_number` | VARCHAR | Número de cuenta operacional |
| `person_id` | INT | FK a persona en sistema fuente |
| `store_id` | INT | FK a tienda (si aplica) |
| `territory_id` | INT | Territorio de ventas |
| `full_name_hash` | VARCHAR(64) | SHA2-256 de `name` |
| `email_address_hash` | VARCHAR(64) | SHA2-256 de `email_address` |
| `phone_hash` | VARCHAR(64) | SHA2-256 de `phone` |
| `_ingested_at` | DATETIME2 | Timestamp de carga en raw |
| `_source_system` | VARCHAR | Sistema origen (`crm`) |
| `_source_entity` | VARCHAR | Tabla fuente (`customers`) |
| `_pipeline_name` | VARCHAR | Nombre del job de ingesta |
| `_batch_id` | VARCHAR(36) | UUID del lote de carga |
| `_raw_hash` | VARCHAR(64) | Hash CDC de todos los campos de negocio |
| `_dbt_loaded_at` | DATETIME | Timestamp de escritura dbt |

### az_addresses

Direcciones físicas de clientes.

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `address_sk` | VARCHAR(64) | Surrogate key — PK en Fabric |
| `address_id` | INT | PK natural |
| `customer_id` | INT | FK a az_customers |
| `customer_sk` | VARCHAR(64) | FK surrogate a az_customers |
| `city` | VARCHAR | Ciudad (no PII) |
| `state_province_id` | INT | Provincia/estado |
| `postal_code` | VARCHAR | Código postal (no PII) |
| `country_region` | VARCHAR | País/región (no PII) |
| `address_line1_hash` | VARCHAR(64) | SHA2-256 de `address_line1` |
| `address_line2_hash` | VARCHAR(64) | SHA2-256 de `address_line2` |
| `_ingested_at` | DATETIME2 | — |
| `_raw_hash` | VARCHAR(64) | — |
| `_dbt_loaded_at` | DATETIME | — |

### az_order_headers

Cabeceras de órdenes de venta. Sin PII.

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `order_header_sk` | VARCHAR(64) | Surrogate key — PK en Fabric |
| `sales_order_id` | INT | PK natural del ERP |
| `customer_id` | INT | FK a az_customers (PK natural) |
| `customer_sk` | VARCHAR(64) | FK surrogate a az_customers |
| `order_date` | DATETIME | Fecha de la orden |
| `due_date` | DATETIME | Fecha de entrega comprometida |
| `ship_date` | DATETIME | Fecha de envío real |
| `status` | TINYINT | Estado de la orden |
| `online_order_flag` | BIT | Canal: online o presencial |
| `sales_order_number` | NVARCHAR | Número legible de la orden |
| `territory_id` | INT | Territorio de venta |
| `sub_total` | DECIMAL | Subtotal antes de impuestos |
| `tax_amt` | DECIMAL | Impuestos |
| `freight` | DECIMAL | Costo de envío |
| `total_due` | DECIMAL | Total a pagar |
| `_ingested_at` | DATETIME2 | — |
| `_raw_hash` | VARCHAR(64) | — |
| `_dbt_loaded_at` | DATETIME | — |

### az_order_details

Líneas de orden (PK compuesta). Sin PII.

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `order_detail_sk` | VARCHAR(64) | Surrogate key — PK en Fabric |
| `sales_order_id` | INT | FK a az_order_headers |
| `sales_order_detail_id` | INT | ID de la línea dentro de la orden |
| `customer_id` | INT | FK a az_customers (desnormalizado) |
| `customer_sk` | VARCHAR(64) | FK surrogate a az_customers |
| `product_id` | INT | FK a az_products |
| `order_qty` | SMALLINT | Cantidad ordenada |
| `unit_price` | DECIMAL | Precio unitario |
| `unit_price_discount` | DECIMAL | Descuento aplicado |
| `line_total` | DECIMAL | Total de la línea (fuente) |
| `_ingested_at` | DATETIME2 | — |
| `_raw_hash` | VARCHAR(64) | — |
| `_dbt_loaded_at` | DATETIME | — |

### az_products

Catálogo de productos. Sin PII.

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `product_sk` | VARCHAR(64) | Surrogate key — PK en Fabric |
| `product_id` | INT | PK natural del ERP |
| `product_name` | NVARCHAR | Nombre del producto |
| `product_number` | NVARCHAR | Código de producto |
| `standard_cost` | DECIMAL | Costo estándar |
| `list_price` | DECIMAL | Precio de lista |
| `color` | NVARCHAR | Color |
| `size` | NVARCHAR | Talla/tamaño |
| `weight` | DECIMAL | Peso |
| `safety_stock_level` | SMALLINT | Nivel de stock de seguridad |
| `reorder_point` | SMALLINT | Punto de reorden |
| `product_category_id` | INT | Categoría |
| `product_subcategory_id` | INT | Subcategoría |
| `sell_start_date` | DATETIME | Inicio de venta |
| `sell_end_date` | DATETIME | Fin de venta |
| `_ingested_at` | DATETIME2 | — |
| `_raw_hash` | VARCHAR(64) | — |
| `_dbt_loaded_at` | DATETIME | — |

### az_employees

Empleados del sistema RRHH. PII hasheado.

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `employee_sk` | VARCHAR(64) | Surrogate key — PK en Fabric |
| `business_entity_id` | INT | PK natural del sistema RRHH |
| `job_title` | NVARCHAR | Título del cargo (no PII) |
| `marital_status` | NCHAR | Estado civil codificado (no PII) |
| `gender` | NCHAR | Género codificado (no PII) |
| `hire_date` | DATE | Fecha de contratación (no PII) |
| `salaried_flag` | BIT | Asalariado o por horas |
| `vacation_hours` | SMALLINT | Horas de vacaciones acumuladas |
| `sick_leave_hours` | SMALLINT | Horas de enfermedad acumuladas |
| `national_id_hash` | VARCHAR(64) | SHA2-256 de `national_id_number` |
| `login_id_hash` | VARCHAR(64) | SHA2-256 de `login_id` |
| `birth_date_hash` | VARCHAR(64) | SHA2-256 de `birth_date` |
| `_ingested_at` | DATETIME2 | — |
| `_raw_hash` | VARCHAR(64) | — |
| `_dbt_loaded_at` | DATETIME | — |

### az_departments

Departamentos del sistema RRHH. Sin PII.

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `department_sk` | VARCHAR(64) | Surrogate key — PK en Fabric |
| `department_id` | SMALLINT | PK natural |
| `department_name` | NVARCHAR | Nombre del departamento |
| `group_name` | NVARCHAR | Agrupación funcional |
| `_ingested_at` | DATETIME2 | — |
| `_raw_hash` | VARCHAR(64) | — |
| `_dbt_loaded_at` | DATETIME | — |

### az_orders

Join analítico desnormalizado: cabecera + detalle + referencias. Sin PII. **Materializado como TABLE (full rebuild)**, no incremental.

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `sales_order_id` | INT | ID de la orden |
| `sales_order_detail_id` | INT | ID de la línea |
| `order_date` | DATETIME | Fecha de la orden |
| `status` | TINYINT | Estado |
| `customer_id` | INT | FK a az_customers |
| `customer_sk` | VARCHAR(64) | FK surrogate a az_customers |
| `product_id` | INT | FK a az_products |
| `order_qty` | SMALLINT | Cantidad |
| `unit_price` | DECIMAL | Precio unitario |
| `unit_price_discount` | DECIMAL | Descuento |
| `line_total_net` | DECIMAL | `qty * price * (1 - discount)` — calculado en dbt |
| `discount_amount` | DECIMAL | `qty * price * discount` — calculado en dbt |
| `_ingested_at` | DATETIME2 | — |
| `_dbt_loaded_at` | DATETIME | — |

---

## Columnas de metadatos de linaje

Todas las tablas `az_*` incluyen estas columnas para trazabilidad end-to-end:

| Columna | Descripción | Uso en Fabric |
| --- | --- | --- |
| `_ingested_at` | Timestamp UTC de cuando el pipeline cargó el dato en raw | Auditoría, particionamiento por fecha de ingesta |
| `_source_system` | Sistema origen (`crm`, `erp`, `hr`) | Filtros, debugging |
| `_source_entity` | Nombre de la tabla fuente | Trazabilidad |
| `_pipeline_name` | Nombre del job de ingesta | Debugging |
| `_batch_id` | UUID del lote de carga | Agrupa todos los registros de una misma ejecución |
| `_raw_hash` | SHA2-256 de todos los campos de negocio | CDC — detectar cambios entre cargas |
| `_dbt_loaded_at` | Timestamp de cuando dbt escribió la fila | Auditoría dbt |

---

## Surrogate keys

Los `*_sk` son el mecanismo de integración entre tablas en Fabric. Se generan con `dbt_utils.generate_surrogate_key` sobre la PK natural y son **reproducibles**: el mismo `customer_id` siempre produce el mismo `customer_sk`.

```text
customer_sk  = hash(customer_id)
employee_sk  = hash(business_entity_id)
product_sk   = hash(product_id)
address_sk   = hash(address_id)
```

Esto significa que si en el proyecto Fabric se necesita regenerar las claves o unir con datos de otra fuente que use la misma convención, se puede calcular el `*_sk` localmente sin depender de la tabla fuente.

---

## Estado actual vs. historia

**La capa `az_*` representa el estado actual** de cada entidad. No hay historia acumulada en SQL Server — cada registro refleja el último valor conocido.

**La historia se construye en Fabric.** El proyecto dbt-fabric debe implementar:

- **SCD Tipo 2** para dimensiones que requieren historial (clientes, productos, empleados)
- **Append log** o tablas de hechos con timestamp para órdenes y eventos transaccionales
- La columna `_ingested_at` y `_raw_hash` permiten detectar qué cambió y cuándo

---

## Patrón CDC que usa este proyecto

Para que el proyecto Fabric entienda cómo se actualizan los datos:

1. La landing zone (`dbt_cibao_raw`) hace **TRUNCATE + full reload** en cada ingesta — mirror del instante actual
2. El campo `_raw_hash` cambia si cualquier campo de negocio cambia
3. dbt hace **merge incremental**: solo inserta/actualiza filas donde `_raw_hash` difiere
4. Un **pre-hook DELETE** elimina de `az_*` los registros que ya no existen en raw (borrados en la fuente)
5. Primera carga: `dbt run --full-refresh` — carga todo; cargas posteriores: `dbt run` — solo deltas

El proyecto Fabric puede asumir que cuando recibe una fila actualizada, el `_raw_hash` ya es distinto al anterior.

---

## Contratos de datos

Los modelos `az_*` tienen `contract_status: visado` en su metadata YAML. Esto significa:

- El schema de columnas no cambia sin revisión de ingeniería
- Los tests de datos están declarados: `not_null`, `unique`, `relationships`, `accepted_values`
- Las claves foráneas entre tablas están validadas

El proyecto Fabric puede confiar en que:
- `customer_sk` en `az_order_headers` siempre existe en `az_customers`
- `product_id` en `az_order_details` siempre existe en `az_products`
- `customer_sk` en `az_orders` siempre existe en `az_customers`

---

## Lo que el proyecto dbt-fabric debe hacer

Con esta base, el proyecto `dbt-fabric` se encarga de:

### 1. Ingestar la capa `az_*` en el Lakehouse

Leer las tablas `db_cibao_dev.azure_fabric.*` de SQL Server y cargarlas en el Lakehouse de Fabric (dev / qa / prod). Esto puede hacerse con:

- **Fabric Data Factory / Pipelines** — copia incremental usando `_raw_hash` o `_dbt_loaded_at`
- **Fabric Dataflows Gen2** — transformación directa en Fabric
- **dbt-fabric adapter** — correr dbt directamente contra el Warehouse de Fabric

### 2. Construir historia (SCD / append)

Implementar la dimensión histórica que este PoC no tiene:

```text
az_customers (estado actual)  →  dim_customers (SCD tipo 2 con valid_from / valid_to)
az_order_details (estado actual)  →  fct_order_lines (append por fecha)
```

### 3. Construir marts analíticos

Sobre las dimensiones e históricas, construir los marts de consumo:

- `mart_ventas` — métricas de ventas por territorio, producto, canal
- `mart_rrhh` — headcount, rotación, distribución por departamento
- `mart_clientes` — segmentación, ciclo de vida, valor

### 4. Mantener la convención de surrogate keys

Usar los mismos `*_sk` de las tablas `az_*` como claves de integración. No regenerar nuevas claves en Fabric para las mismas entidades.

### 5. Documentar la ausencia de PII

En el proyecto Fabric, todos los modelos que vengan de este PoC deben tener en su YAML:

```yaml
meta:
  pii_free: true
  pii_source: dbt-sqlserver-poc
  pii_vault: int_pii_vault_customers   # referencia al vault en SQL Server
```

---

## Ambientes

| Ambiente | SQL Server (este proyecto) | Fabric (proyecto dbt-fabric) |
| --- | --- | --- |
| dev | `db_cibao_dev.azure_fabric.*` | Lakehouse dev |
| qa | `db_cibao_qa.azure_fabric.*` | Lakehouse qa |
| prod | `db_cibao_prod.azure_fabric.*` | Lakehouse prod |

En producción, los modelos `int_pii_vault_*` se excluyen explícitamente:

```bash
dbt run --target prod --exclude tag:local_only
```

---

## Referencia rápida de esquemas de integración

Para el equipo que diseña el proyecto Fabric, las uniones clave entre tablas son:

```sql
-- Órdenes con referencia al cliente
az_order_headers  →  az_customers      ON customer_sk
az_order_details  →  az_order_headers  ON sales_order_id
az_order_details  →  az_products       ON product_id

-- Vista analítica precompilada (az_orders ya tiene todo unido)
az_orders.customer_sk  →  az_customers.customer_sk
az_orders.product_id   →  az_products.product_id

-- Clientes con su dirección
az_addresses.customer_sk  →  az_customers.customer_sk
```

---

## Repositorio de referencia

El código completo de este PoC, incluyendo todos los modelos SQL, YAML, documentación dbt y scripts Docker, está en:

```
dbt-sqlserver-poc/
```

Ejecutar `dbt docs serve` en ese proyecto para explorar el linaje completo, los contratos de datos y la estrategia PII en formato interactivo (`http://localhost:8080`).
