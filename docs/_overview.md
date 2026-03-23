{% docs __overview__ %}
# dbt SQL Server → Azure Fabric PoC

## Objetivo del proyecto

Este proyecto es una **prueba de concepto (PoC)** que demuestra el pipeline completo de ingeniería de datos desde sistemas operacionales hasta **Azure Fabric**, implementando buenas prácticas de dbt, protección de PII, contratos de datos y Change Data Capture (CDC).

Aunque los datos son ficticios (AdventureWorks), **la arquitectura, los patrones y las decisiones de diseño están pensados para ser replicados directamente en el proyecto de producción**. Cada modelo incluye documentación que explica el por qué de cada decisión, no solo el qué.

---

## Fuentes de datos

| Sistema | Schema Raw | Tablas | Contenido |
|---------|-----------|--------|-----------|
| CRM | `raw_crm` | customers, addresses | Clientes y direcciones físicas |
| ERP | `raw_erp` | order_headers, order_details, products | Ciclo completo de ventas |
| RRHH | `raw_hr` | employees, departments | Empleados y estructura organizacional |

Todas las tablas raw son cargadas por un pipeline externo (fuera de dbt) y contienen metadatos de ingesta estandarizados:

| Columna | Descripción |
|---------|-------------|
| `_ingested_at` | Timestamp de carga en raw |
| `_source_system` | Sistema origen (crm, erp, hr) |
| `_source_entity` | Nombre de la tabla en el sistema fuente |
| `_pipeline_name` | Nombre del job de ingesta |
| `_batch_id` | Identificador del lote de carga |
| `_raw_hash` | Hash SHA2_256 de todos los campos de negocio — usado para CDC |
| `_is_deleted` | Flag de borrado lógico (1 = eliminado en fuente) |

---

## Arquitectura de capas

```
[Sistemas operacionales]
    CRM  /  ERP  /  RRHH
           │
           ▼
┌──────────────────────────────────────────────┐
│  RAW — Landing Zone                          │
│  Schema: dbt_cibao_raw  (SQL Server local)   │
│                                              │
│  • Mirror 1:1 de cada tabla fuente           │
│  • TRUNCATE + full reload en cada ingesta    │
│  • Sin transformaciones de negocio           │
│  • Solo agrega metadatos de carga (_*)       │
└──────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────┐
│  STAGING — Normalización                     │
│  Materialización: VIEW  (SQL Server local)   │
│                                              │
│  • Un modelo por tabla raw (1:1)             │
│  • Renombre a snake_case                     │
│  • Cast explícito de tipos                   │
│  • Filtro WHERE _is_deleted = 0              │
│  • Primer contrato de datos (tests)          │
│  • Fuente de verdad para capas superiores    │
└──────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────┐
│  INTERMEDIATE — Enriquecimiento y seguridad  │
│  Materialización: VIEW  (SQL Server local)   │
│                                              │
│  • Deduplicación con ROW_NUMBER()            │
│  • Surrogate keys (dbt_utils)                │
│  • Hash SHA2_256 de campos PII               │
│  • Joins analíticos entre fuentes            │
│  • Bóvedas PII (SOLO local — nunca Azure)    │
└──────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────┐
│  AZURE FABRIC — Capa certificada             │
│  Materialización: incremental/merge + table  │
│                                              │
│  • Una tabla az_ por tabla raw               │
│  • SIN PII en claro — solo hashes            │
│  • CDC via _raw_hash (merge eficiente)       │
│  • Pre-hook elimina borrados de la fuente    │
│  • Contratos de datos visados                │
│  • Lista para cargar a Microsoft Fabric      │
└──────────────────────────────────────────────┘
```

---

## Mapa completo raw → az_

| Tabla raw | Modelo az_ | Campos PII → tratamiento |
|-----------|-----------|--------------------------|
| `raw_crm.customers` | `az_customers` | name / email_address / phone → hash SHA2_256 |
| `raw_crm.addresses` | `az_addresses` | address_line1 / address_line2 → hash SHA2_256 |
| `raw_erp.order_headers` | `az_order_headers` | Sin PII |
| `raw_erp.order_details` | `az_order_details` | Sin PII |
| `raw_erp.products` | `az_products` | Sin PII |
| `raw_hr.employees` | `az_employees` | national_id_number / login_id / birth_date → hash SHA2_256 |
| `raw_hr.departments` | `az_departments` | Sin PII |
| *(join analítico)* | `az_orders` | customer_sk únicamente (no PII) |

---

## Convenciones de nomenclatura

### Prefijos de modelos

| Prefijo | Capa | Ejemplo |
|---------|------|---------|
| `stg_<sistema>__<entidad>` | Staging | `stg_crm__customers` |
| `int_<nombre>` | Intermediate | `int_customers` |
| `int_pii_vault_<entidad>` | Bóveda PII local | `int_pii_vault_customers` |
| `az_<nombre>` | Azure Fabric | `az_customers` |

> La doble barra baja `__` en staging separa el sistema fuente de la entidad,
> siguiendo la convención oficial de dbt para fuentes múltiples.

### Columnas de metadatos de pipeline

Todas las columnas de infraestructura usan prefijo `_` para distinguirlas de los campos de negocio:

| Columna | Presente en |
|---------|-------------|
| `_ingested_at` | raw, staging, az_ |
| `_source_system` | raw, staging, az_ |
| `_source_entity` | raw, staging, az_ |
| `_pipeline_name` | raw, staging, az_ |
| `_batch_id` | raw, staging, az_ |
| `_raw_hash` | raw, staging, az_ |
| `_is_deleted` | raw (filtrado en staging) |
| `_dbt_loaded_at` | az_ (timestamp de escritura dbt) |

### Columnas hasheadas (PII)

Los campos PII en la capa az_ usan el sufijo `_hash`:
`full_name_hash`, `email_address_hash`, `phone_hash`, `national_id_hash`, `login_id_hash`, `birth_date_hash`, `address_line1_hash`, `address_line2_hash`

---

## Buenas prácticas implementadas

### 1. Una fuente de verdad por entidad
Staging expone exactamente los datos raw normalizados. Ninguna capa downstream
transforma lo que ya transformó staging. Cada capa tiene responsabilidad única.

### 2. Contratos de datos en YAML
Cada modelo tiene tests declarativos (`not_null`, `unique`, `relationships`,
`accepted_values`). Los modelos az_ son contratos **visados** (`contract_status: visado`)
que no cambian sin revisión de ingeniería.

### 3. Documentación como código
Toda la documentación vive en bloques {% raw %}`{% docs %}`{% endraw %} en archivos `.md`,
referenciados desde los YAML con {% raw %}`'{{ doc("nombre") }}'`{% endraw %}.
Los comentarios en SQL se limitan a 2 líneas — el detalle vive en docs.

### 4. Surrogate keys con dbt_utils
`dbt_utils.generate_surrogate_key(['campo_pk'])` genera claves sintéticas
reproducibles. Nunca se usa la PK natural del sistema fuente como clave de
integración entre capas cloud.

### 5. PII hasheado en la capa az_
Ningún dato personal viaja a Azure en claro. SHA2_256 sobre el valor raw
garantiza que el hash es idéntico en `az_*` y en `int_pii_vault_*`,
permitiendo verificación cruzada. Ver `doc("pii_strategy")`.

### 6. CDC eficiente con _raw_hash
La capa az_ solo procesa filas nuevas o modificadas comparando `_raw_hash`.
Un pre-hook elimina las filas que desaparecieron de la fuente.
Ver `doc("cdc_pattern")`.

### 7. Metadata `meta:` en todos los modelos
```yaml
meta:
  owner: data-engineering
  pii_free: true
  contract_status: visado
  pii_vault: int_pii_vault_customers   # para modelos con PII hasheado
```

### 8. Compatibilidad SQL Server 2016+
Sin `TRIM()` (usar `LTRIM(RTRIM())`), sin `STRING_AGG`, sin `CONCAT_WS`.
Hashes con `CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ...), 2)`.

---

## Cómo navegar el proyecto

```
models/
├── staging/
│   ├── crm/          ← stg_crm__customers, stg_crm__addresses
│   ├── erp/          ← stg_erp__order_headers, stg_erp__order_details, stg_erp__products
│   └── hr/           ← stg_hr__employees, stg_hr__departments
├── intermediate/     ← int_customers, int_employees, int_orders
│                       int_pii_vault_customers, int_pii_vault_employees
├── azure_fabric/     ← az_customers, az_addresses, az_order_headers,
│                       az_order_details, az_products, az_employees,
│                       az_departments, az_orders
└── docs/             ← _overview.md, _columns.md, _sources.md,
                        _staging.md, _intermediate.md, _azure_fabric.md
```

Para explorar la linaje completo: `dbt docs serve` → grafo de linaje.
Para ejecutar todo: `dbt run && dbt test`.
Para primera carga: `dbt run --full-refresh`.
{% enddocs %}


{% docs pii_strategy %}
# Estrategia de protección de PII

## Clasificación de campos PII

| Campo | Clasificación | Tratamiento |
|-------|--------------|-------------|
| name (cliente) | PII — identificador | Hash SHA2_256 en az_, claro en vault |
| email_address | PII — contacto | Hash SHA2_256 en az_, claro en vault |
| phone | PII — contacto | Hash SHA2_256 en az_, claro en vault |
| address_line1/2 | PII — domicilio | Hash SHA2_256 en az_, claro en stg_ |
| national_id_number | PII — identidad legal | Hash SHA2_256 en az_, claro en vault |
| login_id | PII — acceso | Hash SHA2_256 en az_, claro en vault |
| birth_date | PII — personal | Hash SHA2_256 en az_, claro en vault |

## Regla fundamental

> Los hashes en `az_*` y en `int_pii_vault_*` se calculan sobre los **valores RAW
> de staging**. No sobre valores normalizados. Esto garantiza que el hash de un
> valor específico produce el mismo resultado en ambas capas, permitiendo
> verificación cruzada sin exponer el dato en claro.

## Flujo de un campo PII

```
raw_crm.customers.name = "John Doe"
         │
         ▼
stg_crm__customers.name = "John Doe"         (sin cambios, valor raw)
         │
    ┌────┴────────────────────────────────┐
    │                                     │
    ▼                                     ▼
az_customers                    int_pii_vault_customers
  full_name_hash =                name = "John Doe"        ← PII en claro
  SHA2_256("John Doe")            full_name_hash =
                                  SHA2_256("John Doe")     ← mismo hash
```

## Cómo recuperar PII desde Azure

Dado un `customer_sk` o `customer_id` de Azure Fabric:
```sql
-- En SQL Server local (NUNCA ejecutar en Azure)
SELECT name, email_address, phone
FROM intermediate.int_pii_vault_customers
WHERE customer_sk = '<valor de az_customers>'
```

Dado un hash para verificar sin exponer PII:
```sql
SELECT customer_sk, customer_id
FROM intermediate.int_pii_vault_customers
WHERE email_address_hash = CONVERT(VARCHAR(64),
    HASHBYTES('SHA2_256', ISNULL(CAST('usuario@ejemplo.com' AS NVARCHAR(MAX)), '')), 2)
```

## Lo que NO viaja a Azure

- Ningún campo PII en claro
- Los modelos `int_pii_vault_*` (tags: `local_only`, `restricted`)
- Las vistas de staging e intermediate (son efímeras en SQL Server)
{% enddocs %}


{% docs cdc_pattern %}
# Patrón CDC en la capa Azure Fabric

## Filosofía de carga

La capa raw es siempre un **mirror completo** del instante actual: cada ingesta
hace TRUNCATE + full reload. No hay historia en raw.

La capa Azure Fabric mantiene el **estado actual** usando merge incremental:
solo procesa filas que cambiaron (o son nuevas), y elimina las que dejaron de
existir en la fuente. La historia (SCD tipo 2, append log) se construirá en
Azure Fabric después de recibir los datos.

## Cómo funciona el CDC

**1. Detección de cambios** — campo `_raw_hash`

El pipeline de ingesta calcula un hash SHA2_256 de todos los campos de negocio
de la fila y lo almacena en `_raw_hash`. Si cualquier campo cambia, el hash cambia.

**2. Merge incremental** — solo filas nuevas o modificadas

{% raw %}
```sql
-- Cada az_ filtra con este patrón en modo incremental:
changed AS (
    SELECT s.*
    FROM source AS s
    LEFT JOIN {{ this }} AS t ON s.pk = t.pk
    WHERE t.pk IS NULL           -- fila nueva
       OR s._raw_hash <> t._raw_hash  -- fila modificada
)
```
{% endraw %}

**3. Pre-hook de borrado** — eliminar registros que ya no existen

{% raw %}
```sql
-- Antes del merge, se borran filas huérfanas:
DELETE FROM {{ this }}
WHERE pk NOT IN (SELECT pk FROM {{ ref('stg_...') }})
```

Para claves compuestas se usa `NOT EXISTS`:
```sql
DELETE t FROM {{ this }} t
WHERE NOT EXISTS (
    SELECT 1 FROM {{ ref('stg_...') }} s
    WHERE t.pk1 = s.pk1 AND t.pk2 = s.pk2
)
```
{% endraw %}

## Primera carga (full load)

En la primera ejecución (`dbt run --full-refresh`) el bloque {% raw %}`{% if is_incremental() %}`{% endraw %}
evalúa a falso y se carga toda la tabla completa. El filtro CDC no aplica.

## az_orders — excepción

`az_orders` es un join analítico de múltiples fuentes. Se materializa como `table`
(full rebuild en cada run) para garantizar consistencia sin complejidad de CDC
multi-fuente.
{% enddocs %}
