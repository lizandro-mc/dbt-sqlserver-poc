# dbt SQL Server → Azure Fabric PoC

Pipeline de ingeniería de datos desde sistemas operacionales hasta una capa certificada lista para cargar a **Microsoft Fabric**. Implementa dbt sobre SQL Server local (Docker) como plataforma de transformación, protección de PII con SHA2-256, Change Data Capture (CDC) basado en `_raw_hash` y contratos de datos declarativos en YAML.

Los datos son ficticios (AdventureWorks2016), pero la arquitectura, los patrones y las convenciones están diseñados para trasladarse directamente al proyecto de producción.

---

## Arquitectura

```text
[Sistemas operacionales]
  CRM  /  ERP  /  RRHH
         │
         ▼  (init scripts Docker — simula pipeline de ingesta)
┌─────────────────────────────────────────────┐
│  dbt_cibao_raw  — Landing Zone              │
│  SQL Server local (Docker)                  │
│                                             │
│  raw_crm.customers      ~19 000 filas       │
│  raw_crm.addresses      ~19 000 filas       │
│  raw_erp.order_headers  ~31 000 filas       │
│  raw_erp.order_details ~121 000 filas       │
│  raw_erp.products          ~504 filas       │
│  raw_hr.employees          ~290 filas       │
│  raw_hr.departments         ~16 filas       │
│                                             │
│  Cada tabla incluye metadatos:              │
│  _ingested_at  _source_system  _batch_id    │
│  _raw_hash     _is_deleted     _pipeline_name│
└─────────────────────────────────────────────┘
         │  (dbt run)
         ▼
┌─────────────────────────────────────────────┐
│  db_cibao_dev  — Transformaciones dbt       │
│                                             │
│  staging.*       VIEW — normalización 1:1   │
│  intermediate.*  VIEW — enriquecimiento,    │
│                  surrogate keys, hashes PII │
│  azure_fabric.*  TABLE — capa certificada   │
│                  sin PII en claro           │
└─────────────────────────────────────────────┘
         │
         ▼  ← ENTRADA DEL PROYECTO dbt-fabric
┌─────────────────────────────────────────────┐
│  Microsoft Fabric — Lakehouse               │
│  Ambientes: dev / qa / prod                 │
│                                             │
│  Recibe la capa azure_fabric.*              │
│  Sin PII — solo hashes SHA2-256             │
│  Historia SCD tipo 2 / append log           │
│  Marts analíticos finales                   │
└─────────────────────────────────────────────┘
```

---

## Modelos dbt (20 modelos)

### Staging — 7 modelos (VIEW)

| Modelo | Fuente raw | Descripción |
| --- | --- | --- |
| `stg_crm__customers` | `raw_crm.customers` | Clientes normalizados, filtro `_is_deleted=0` |
| `stg_crm__addresses` | `raw_crm.addresses` | Direcciones físicas |
| `stg_erp__order_headers` | `raw_erp.order_headers` | Cabeceras de orden de venta |
| `stg_erp__order_details` | `raw_erp.order_details` | Líneas de orden (PK compuesta) |
| `stg_erp__products` | `raw_erp.products` | Catálogo de productos |
| `stg_hr__employees` | `raw_hr.employees` | Empleados |
| `stg_hr__departments` | `raw_hr.departments` | Departamentos |

### Intermediate — 5 modelos (VIEW)

| Modelo | Descripción |
| --- | --- |
| `int_customers` | Clientes + direcciones, deduplicados, `customer_sk`, PII hasheado |
| `int_employees` | Empleados deduplicados, `employee_sk`, PII hasheado |
| `int_orders` | Cabecera + detalle + `customer_sk`, campos calculados |
| `int_pii_vault_customers` | **LOCAL ONLY** — PII en claro para desanonimización controlada |
| `int_pii_vault_employees` | **LOCAL ONLY** — PII en claro para desanonimización controlada |

### Azure Fabric — 8 modelos (TABLE incremental/merge)

| Modelo | Fuente | PII | Descripción |
| --- | --- | --- | --- |
| `az_customers` | `stg_crm__customers` | hashes | Clientes sin PII, `customer_sk` |
| `az_addresses` | `stg_crm__addresses` | hashes | Direcciones con address_line hasheado |
| `az_order_headers` | `stg_erp__order_headers` | ninguno | Cabeceras de orden |
| `az_order_details` | `stg_erp__order_details` | ninguno | Líneas de orden |
| `az_products` | `stg_erp__products` | ninguno | Catálogo de productos |
| `az_employees` | `stg_hr__employees` | hashes | Empleados sin PII, `employee_sk` |
| `az_departments` | `stg_hr__departments` | ninguno | Departamentos |
| `az_orders` | `int_orders` | ninguno | Join analítico (materializado como TABLE) |

---

## Protección de PII

Ningún campo personal viaja a la capa `azure_fabric` en claro. Todos los campos PII se reemplazan por su hash SHA2-256 calculado sobre el **valor raw de staging** (sin normalización).

| Campo | Tabla az_ | Hash resultante |
| --- | --- | --- |
| `name` | az_customers | `full_name_hash` |
| `email_address` | az_customers | `email_address_hash` |
| `phone` | az_customers | `phone_hash` |
| `address_line1/2` | az_addresses | `address_line1_hash`, `address_line2_hash` |
| `national_id_number` | az_employees | `national_id_hash` |
| `login_id` | az_employees | `login_id_hash` |
| `birth_date` | az_employees | `birth_date_hash` |

Los modelos `int_pii_vault_*` conservan los valores en claro en SQL Server local para desanonimización controlada. Tienen tags `local_only` y `restricted` — **nunca se deben ejecutar contra Azure**.

Para excluirlos al ejecutar contra Fabric:

```bash
dbt run --target prod --exclude tag:local_only
```

---

## Patrón CDC

La capa `azure_fabric` solo procesa filas nuevas o modificadas comparando `_raw_hash`. Un pre-hook elimina registros que desaparecieron de la fuente.

```text
raw (TRUNCATE + full reload en cada ingesta)
  → _raw_hash cambia si cualquier campo de negocio cambia
  → az_ merge: solo inserta/actualiza filas con hash distinto
  → az_ pre-hook: DELETE de filas no presentes en raw (borrados)
```

Primera carga: `dbt run --full-refresh` — carga toda la tabla.
Cargas posteriores: `dbt run` — solo procesa deltas.

`az_orders` es la excepción: se materializa como `table` (full rebuild) por ser un join analítico de múltiples fuentes.

---

## La capa `azure_fabric` como fuente para Fabric

La capa `db_cibao_dev.azure_fabric.*` es el **output certificado** de este PoC y la entrada del proyecto `dbt-fabric`. Lo que el proyecto Fabric recibe:

- Tablas con estado actual (no historia — la historia se construye en Fabric con SCD tipo 2 o append log)
- Sin PII en claro — solo hashes SHA2-256 comparables entre tablas
- `customer_sk` y `employee_sk` como surrogate keys consistentes entre `az_customers`, `az_employees` y `az_orders`
- Columnas de metadatos de linaje: `_ingested_at`, `_source_system`, `_batch_id`, `_raw_hash`, `_dbt_loaded_at`
- Contratos de datos visados (`contract_status: visado`) — el schema no cambia sin revisión de ingeniería

### Convención de surrogate keys

Los `*_sk` se generan con `dbt_utils.generate_surrogate_key` sobre la PK natural. Son reproducibles: el mismo `customer_id` siempre produce el mismo `customer_sk` en SQL Server y en Fabric.

### Verificación cruzada de PII desde Fabric

Dado un `customer_sk` de Fabric, recuperar PII en SQL Server local:

```sql
-- En SQL Server local — NUNCA ejecutar en Azure
SELECT name, email_address, phone
FROM db_cibao_dev.intermediate.int_pii_vault_customers
WHERE customer_sk = '<valor de az_customers.customer_sk>'
```

---

## Inicio rápido

```bash
# 1. Levantar SQL Server + cargar AdventureWorks (~60-90 seg)
cd sqlserver && docker compose up -d && cd ..

# 2. Entorno Python
python3 -m venv .venv
source .venv/bin/activate
pip install dbt-sqlserver==1.9.0

# 3. Variables de entorno + verificar conexión
source .env
dbt debug

# 4. Primera carga completa
dbt run --full-refresh

# 5. Tests
dbt test

# 6. Documentación interactiva
dbt docs generate && dbt docs serve
# → http://localhost:8080
```

Cargas posteriores (solo deltas CDC):

```bash
source .venv/bin/activate && source .env && dbt run
```

---

## Estructura del repositorio

```text
dbt-sqlserver-poc/
├── models/
│   ├── docs/                       # Bloques {% docs %} — documentación dbt
│   │   ├── _overview.md            # __overview__ + project_overview + pii_strategy + cdc_pattern
│   │   ├── _columns.md             # Columnas compartidas (_ingested_at, _raw_hash, *_sk, *_hash)
│   │   ├── _sources.md             # Descripción de fuentes raw
│   │   ├── _staging.md             # Descripción de modelos staging
│   │   ├── _intermediate.md        # Descripción de modelos intermediate y vaults PII
│   │   └── _azure_fabric.md        # Descripción de modelos az_ y contratos de datos
│   ├── staging/
│   │   ├── crm/                    # stg_crm__* + sources + models YAML
│   │   ├── erp/                    # stg_erp__* + sources + models YAML
│   │   └── hr/                     # stg_hr__* + sources + models YAML
│   ├── intermediate/               # int_customers, int_employees, int_orders
│   │                               # int_pii_vault_customers, int_pii_vault_employees
│   └── azure_fabric/               # az_customers, az_addresses, az_order_headers,
│                                   # az_order_details, az_products, az_employees,
│                                   # az_departments, az_orders
├── sqlserver/
│   ├── docker-compose.yml          # SQL Server 2017 + Adminer
│   └── init/                       # Scripts de inicialización automática
│       ├── 01_create_databases.sql
│       ├── 02_create_tables.sql
│       └── 03_load_adventureworks.sql
├── .env                            # Credenciales locales (no subir a git)
├── dbt_project.yml                 # Configuración dbt — capas, materialización, tags
├── profiles.yml                    # Conexión a SQL Server (lee SQL_SERVER_PASSWORD del env)
├── packages.yml                    # dbt_utils 1.3.0
├── QUICKSTART.md                   # Guía de instalación paso a paso
├── ADVENTUREWORKS_SETUP.md         # Cómo funcionan los init scripts Docker
└── AZURE_SQL_SERVER_SETUP.md       # Cómo apuntar a Azure Fabric o Azure SQL en producción
```

---

## Bases de datos en Docker

| Base de datos | Propósito |
| --- | --- |
| `AdventureWorks2016` | Fuente de datos original (Microsoft sample) |
| `dbt_cibao_raw` | Landing zone — mirror con metadata de pipeline |
| `db_cibao_dev` | Target dbt — staging, intermediate, azure_fabric |

---

## Convenciones de nomenclatura

| Prefijo | Capa | Ejemplo |
| --- | --- | --- |
| `stg_<sistema>__<entidad>` | Staging | `stg_crm__customers` |
| `int_<nombre>` | Intermediate | `int_customers` |
| `int_pii_vault_<entidad>` | Bóveda PII local | `int_pii_vault_customers` |
| `az_<nombre>` | Azure Fabric | `az_customers` |

Columnas de metadatos de pipeline usan prefijo `_` (ej. `_ingested_at`, `_raw_hash`).
Hashes PII usan sufijo `_hash` (ej. `full_name_hash`, `email_address_hash`).
La doble barra baja `__` en staging separa sistema fuente de entidad (convención oficial dbt).

---

## Herramientas

- **dbt docs**: `http://localhost:8080` — documentación completa con linaje y contratos
- **Adminer** (UI SQL): `http://localhost:8888`
  - Sistema: MS SQL | Servidor: `sqlserver-cibao` | Usuario: `sa`

---

## Documentación adicional

| Archivo | Contenido |
| --- | --- |
| [QUICKSTART.md](QUICKSTART.md) | Instalación paso a paso, troubleshooting |
| [ADVENTUREWORKS_SETUP.md](ADVENTUREWORKS_SETUP.md) | Init scripts Docker, reinicialización |
| [AZURE_SQL_SERVER_SETUP.md](AZURE_SQL_SERVER_SETUP.md) | Configurar target prod para Azure Fabric o Azure SQL |
