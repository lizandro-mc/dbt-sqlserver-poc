# 🚀 Quick Start: dbt-gov-cibao PoC

Este documento te guía paso a paso para iniciar el PoC de dbt + Fabric + Azure.

---

## ⏰ Fase 1: SQL Server 2016 + dbt (4 días)

### Día 1: Setup Infraestructura SQL Server

**1.1 Instalar/Verificar SQL Server 2016**
```bash
# Verificar que SQL Server 2016 está corriendo
# En Windows, Services > SQL Server (MSSQLSERVER)
# En macOS/Linux: usar Docker o VM
```

**1.2 Descargar AdventureWorks2016**
```bash
# Ir a: https://github.com/Microsoft/sql-server-samples/releases/tag/adventureworks
# Descargar: AdventureWorks2016.bak (~46.7 MB)
# Guardar en: C:\Backups\ o tu carpeta preferida
```

**1.3 Restaurar Base de Datos**

Abrir SSMS (SQL Server Management Studio) o Azure Data Studio:

```sql
-- Restaurar AdventureWorks
USE master;
RESTORE DATABASE AdventureWorks2016
  FROM DISK = 'C:\Backups\AdventureWorks2016.bak'
  WITH REPLACE;
GO

-- Verificar
SELECT COUNT(*) as TableCount
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'AdventureWorks2016'
  AND TABLE_TYPE = 'BASE TABLE';
-- Should return: 71 tablas
```

**1.4 Crear Bases de Datos Landing/Dev/Prod**

Ejecutar el script SQL completo en: `ADVENTUREWORKS_SETUP.md` (Paso 4 y 5)

Esto crea:
- ✅ `dbt-cibao-raw` (Landing/Raw con schemas raw_crm, raw_erp, raw_hr)
- ✅ `db-cibao-dev` (Desarrollo con schemas staging, intermediate, marts)
- ✅ `db-cibao-prod` (Producción, similar a dev)

Verifica con:
```sql
SELECT * FROM sys.databases WHERE name LIKE 'db-cibao%' OR name LIKE 'dbt-cibao%';
```

---

### Día 2: Crear Repo dbt y Configurar Conexión

**2.1 Crear Repositorio dbt-gov-cibao**

```bash
# En tu DevOps (Azure DevOps, GitHub, etc)
# Crear nuevo repo: dbt-gov-cibao
# Clonar localmente

git clone https://dev.azure.com/yourorg/yourproject/_git/dbt-gov-cibao
cd dbt-gov-cibao
```

**2.2 Inicializar Proyecto dbt**

```bash
# Instalar dbt para SQL Server
pip install dbt-sqlserver

# O si prefieres otra versión:
pip install dbt-core dbt-sqlserver

# Crear estructura inicial (opcional, también puedes usar los templates)
dbt init

# Verificar versión
dbt --version
```

**2.3 Configurar profiles.yml**

```bash
# Crear archivo de conexión
# En macOS/Linux:
mkdir -p ~/.dbt

# Copiar el template que preparé: profiles_template.yml
# Editarlo con tus credenciales
nano ~/.dbt/profiles.yml
```

**Contenido mínimo de ~/.dbt/profiles.yml:**

```yaml
dbt_gov_cibao:
  target: dev
  outputs:
    dev:
      type: sqlserver
      driver: 'ODBC Driver 17 for SQL Server'
      server: 'localhost'           # o tu server
      port: 1433
      database: 'db-cibao-dev'
      schema: 'staging'
      username: 'sa'                # o tu usuario
      password: 'tu_contraseña'
      authentication: 'sql'
      threads: 4
      query_timeout_in_seconds: 300
```

**2.4 Verificar Conexión**

```bash
cd dbt-gov-cibao

# Debug de conexión
dbt debug

# Expected output:
#   Connection test: [ok]
```

**2.5 Crear Estructura de Directorios**

```bash
# En la raíz de dbt-gov-cibao/

mkdir -p models/{staging,intermediate,marts}
mkdir -p macros tests seeds analysis docs

# Copiar archivos template
cp dbt_project_template.yml dbt_project.yml
cp /path/to/MODELO_DBT_EXAMPLES.md docs/MODELS_GUIDE.md
```

**2.6 Actualizar dbt_project.yml**

Editar `dbt_project.yml` con los contenidos de `dbt_project_template.yml`.

```bash
nano dbt_project.yml
```

---

### Día 3: Implementar Modelos Staging

**3.1 Crear macros**

Crear archivo: `macros/get_hash_key.sql`

```sql
{% macro get_hash_key(column) %}
  CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONVERT(VARCHAR(MAX), {{ column }})), 2)
{% endmacro %}
```

Crear archivo: `macros/generate_surrogate_key.sql`

```sql
{% macro generate_surrogate_key(columns) %}
  CONVERT(VARCHAR(64), HASHBYTES('SHA2_256',
    CONCAT(
      {% for col in columns %}
        CONVERT(VARCHAR(MAX), {{ col }})
        {% if not loop.last %}, '||', {% endif %}
      {% endfor %}
    )
  ), 2)
{% endmacro %}
```

**3.2 Crear Archivo YAML de Sources y Tests**

Crear: `models/staging/_stg_models.yml`

```yaml
version: 2

sources:
  - name: raw_crm
    database: dbt-cibao-raw
    schema: raw_crm
    tables:
      - name: customers
        columns:
          - name: customer_id
            tests: [unique, not_null]
      - name: addresses

  - name: raw_erp
    database: dbt-cibao-raw
    schema: raw_erp
    tables:
      - name: order_headers
        columns:
          - name: sales_order_id
            tests: [unique, not_null]
      - name: order_details
      - name: products
        columns:
          - name: product_id
            tests: [unique, not_null]

  - name: raw_hr
    database: dbt-cibao-raw
    schema: raw_hr
    tables:
      - name: employees
        columns:
          - name: business_entity_id
            tests: [unique, not_null]
      - name: departments

models:
  - name: stg_crm_customers
    description: "Cleaned CRM customers"
    columns:
      - name: customer_id
        tests: [unique, not_null]
      - name: source_system
        tests:
          - accepted_values:
              values: ['CRM']

  - name: stg_erp_orders
    description: "Cleaned ERP orders"
    columns:
      - name: sales_order_id
        tests: [unique, not_null]
```

**3.3 Crear Modelos Staging**

Crear: `models/staging/stg_crm_customers.sql`

```sql
WITH source AS (
  SELECT
    customer_id,
    name,
    email_address,
    phone,
    _load_ts,
    _load_dt,
    _source_system
  FROM {{ source('raw_crm', 'customers') }}
  WHERE _is_active = 1
)

, cleaned AS (
  SELECT
    customer_id,
    UPPER(TRIM(name)) as customer_name,
    LOWER(TRIM(email_address)) as email_address,
    TRIM(phone) as phone_number,
    _load_ts as load_timestamp,
    _load_dt as load_date,
    _source_system as source_system,
    CURRENT_TIMESTAMP as _dbt_processed_at
  FROM source
)

SELECT * FROM cleaned
```

**3.4 Crear stg_erp_orders.sql**

```sql
WITH source AS (
  SELECT
    sales_order_id,
    customer_id,
    order_date,
    status,
    sub_total,
    tax_amt,
    freight,
    total_due,
    _load_ts,
    _load_dt,
    _source_system
  FROM {{ source('raw_erp', 'order_headers') }}
  WHERE _is_active = 1
)

SELECT
  sales_order_id,
  customer_id,
  order_date,
  status,
  CAST(sub_total AS DECIMAL(18, 2)) as subtotal,
  CAST(tax_amt AS DECIMAL(18, 2)) as tax_amount,
  CAST(freight AS DECIMAL(18, 2)) as freight_amount,
  CAST(total_due AS DECIMAL(18, 2)) as total_due_amount,
  _load_ts as load_timestamp,
  _load_dt as load_date,
  _source_system as source_system
FROM source
```

**3.5 Ejecutar Modelos**

```bash
# Ejecutar solo staging
dbt run --select staging

# Expected:
#   Creating table db-cibao-dev.staging.stg_crm_customers
#   Creating table db-cibao-dev.staging.stg_erp_orders
#   Completed successfully
```

**3.6 Correr Tests**

```bash
dbt test --select staging

# Expected:
#   Completed: 1 Passed, 0 Failed
```

---

### Día 4: Implementar Intermediate + Marts

**4.1 Crear Modelos Intermediate**

Crear: `models/intermediate/_int_models.yml`

```yaml
models:
  - name: int_customers_hashed
    columns:
      - name: customer_key
        tests: [unique, not_null]
```

Crear: `models/intermediate/int_customers_hashed.sql`

```sql
WITH customers AS (
  SELECT * FROM {{ ref('stg_crm_customers') }}
)

SELECT
  {{ generate_surrogate_key(['customer_id', 'source_system']) }} as customer_key,
  customer_id,
  source_system,
  {{ get_hash_key('customer_name') }} as customer_name_hash,
  {{ get_hash_key('email_address') }} as email_address_hash,
  load_timestamp,
  load_date
FROM customers
```

**4.2 Crear Modelos Marts**

Crear: `models/marts/_marts_models.yml`

```yaml
models:
  - name: dim_customers
    description: "Customer dimension"
    columns:
      - name: customer_key
        tests: [unique, not_null]

  - name: fct_orders
    description: "Orders fact table"
    columns:
      - name: sales_order_id
        tests: [unique, not_null]
```

Crear: `models/marts/dim_customers.sql`

```sql
SELECT
  customer_key,
  customer_id,
  customer_name_hash,
  email_address_hash,
  source_system,
  load_date,
  CURRENT_TIMESTAMP as updated_at
FROM {{ ref('int_customers_hashed') }}
```

Crear: `models/marts/fct_orders.sql`

```sql
SELECT
  sales_order_id,
  customer_id,
  order_date,
  status,
  subtotal,
  tax_amount,
  freight_amount,
  total_due_amount,
  load_date,
  CURRENT_TIMESTAMP as updated_at
FROM {{ ref('stg_erp_orders') }}
```

**4.3 Ejecutar Todo**

```bash
# Ejecutar todos los modelos
dbt run

# Tests completos
dbt test

# Generar documentación
dbt docs generate
dbt docs serve  # Abre http://localhost:8000

# Expected:
#   Completed successfully
```

---

## 📊 Validar Datos en SQL Server

```sql
-- Verificar tablas creadas
SELECT COUNT(*) as RecordCount
FROM [db-cibao-dev].[marts].[dim_customers];

SELECT COUNT(*) as RecordCount
FROM [db-cibao-dev].[marts].[fct_orders];

-- Ver datos sample
SELECT TOP 5 * FROM [db-cibao-dev].[marts].[dim_customers];
SELECT TOP 5 * FROM [db-cibao-dev].[marts].[fct_orders];
```

---

## 🔄 Fase 2: Data Factory (2-3 días)

**Próxima fase**: Crear pipelines en Azure Data Factory para:
1. Copiar datos desde `db-cibao-dev.marts` hacia ADLS (landing)
2. Implementar data contracts
3. Cargar en Lakehouse

(Documentación en próximo documento)

---

## 🎯 Fase 3: Fabric Semantic Layer (3-4 días)

**Final fase**: Crear workspaces en Fabric y conectar semantic models.

(Documentación en próximo documento)

---

## 📋 Checklist Fase 1

- [ ] SQL Server 2016 con AdventureWorks2016 restaurado
- [ ] Bases de datos creadas: dbt-cibao-raw, db-cibao-dev, db-cibao-prod
- [ ] Repo dbt-gov-cibao creado
- [ ] dbt instalado, profiles.yml configurado
- [ ] `dbt debug` exitoso
- [ ] Modelos staging creados y ejecutados
- [ ] Modelos intermediate creados y ejecutados
- [ ] Modelos marts creados y ejecutados
- [ ] Tests pasando 100%
- [ ] Documentación generada y publicada
- [ ] Datos validados en SQL Server

---

## 🚨 Troubleshooting

**Error: "Connection test failed"**
```bash
# Verificar ODBC Driver
isql -l  # Ver drivers disponibles

# Instalar si falta
# En Windows: https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server
# En macOS: brew install odbc-sqlserver
```

**Error: "Database not found"**
```sql
-- Verificar DB existe
SELECT name FROM sys.databases WHERE name LIKE 'db-cibao%';
```

**Error: "HASHBYTES not recognized"**
- Verificar que SQL Server 2016 está corriendo (no Express limitada)
- Algunos comandos requieren SQL Server 2016 SP3+

---

## 📚 Referencias

- **DBT Docs**: https://docs.getdbt.com/
- **dbt-sqlserver**: https://github.com/dbt-labs/dbt-sqlserver
- **Modern Data Stack**: https://lizandro-mc.github.io/modern-data-stack/
- **Existing dbt Project**: https://velomaxdbtdocs.z13.web.core.windows.net/

---

## ✅ Próximos Pasos

1. Completar Fase 1 según checklist
2. Documentar todos los modelos en `_models.yml`
3. Crear CI/CD pipeline en Azure DevOps
4. Proceder a Fase 2: Data Factory

¡Buena suerte! 🚀
