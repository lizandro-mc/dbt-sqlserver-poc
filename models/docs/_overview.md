{% docs project_overview %}
# dbt SQL Server → Azure Fabric PoC

Proyecto de ingeniería de datos que cubre el flujo completo desde fuentes operacionales hasta una capa certificada lista para cargar a **Azure Fabric**.

## Fuentes de datos

| Sistema | Schema Raw | Contenido |
|---------|-----------|-----------|
| CRM | `raw_crm` | Clientes y direcciones |
| ERP | `raw_erp` | Órdenes, detalle de órdenes y productos |
| RRHH | `raw_hr` | Empleados y departamentos |

Todas las tablas raw incluyen metadatos de ingesta añadidos por el pipeline
(`_ingested_at`, `_source_system`, `_raw_hash`, `_is_deleted`, etc.).

## Arquitectura de capas

```
[Sistemas fuente]
    CRM / ERP / RRHH
         │
         ▼
[RAW — Landing Zone]  ← SQL Server (dbt_cibao_raw)
    Mirror completo de cada tabla
    Siempre TRUNCATE + full reload
    Sin transformaciones, solo metadatos de carga
         │
         ▼
[STAGING — Normalización]  ← vistas
    • Cast de tipos
    • Renombre de columnas a snake_case
    • Filtro de borrados lógicos (_is_deleted = 0)
    • Un modelo por tabla raw
    • Contrato de datos (tests not_null, unique, relationships)
         │
         ▼
[INTERMEDIATE — Enriquecimiento y seguridad]  ← vistas
    • Deduplicación y surrogate keys
    • Hash SHA2_256 de campos PII
    • Joins entre fuentes
    • Modelos de bóveda PII (SOLO SQL Server local)
         │
         ▼
[AZURE FABRIC — Capa cloud]  ← tablas incrementales (merge)
    • Una tabla az_ por cada tabla raw
    • Sin PII en claro — solo hashes
    • CDC via _raw_hash (solo procesa filas nuevas o modificadas)
    • Pre-hook borra registros eliminados en la fuente
    • Contratos de datos visados
```

## Mapa raw → az_

| Raw | az_ | PII |
|-----|-----|-----|
| raw_crm.customers | az_customers | name/email/phone → hash |
| raw_crm.addresses | az_addresses | address_line1/2 → hash |
| raw_erp.order_headers | az_order_headers | Sin PII |
| raw_erp.order_details | az_order_details | Sin PII |
| raw_erp.products | az_products | Sin PII |
| raw_hr.employees | az_employees | national_id/login/birth_date → hash |
| raw_hr.departments | az_departments | Sin PII |
| *(join analítico)* | az_orders | customer_sk únicamente |

## Convenciones de nomenclatura

- `stg_<sistema>__<entidad>` — modelos staging
- `int_<nombre>` — modelos intermediate
- `az_<nombre>` — modelos Azure Fabric
- `int_pii_vault_<entidad>` — bóvedas PII locales (NUNCA a Azure)
- `_col` — columnas de metadatos de pipeline
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
