# dbt SQL Server → Azure Fabric PoC

Prueba de concepto de un pipeline de ingeniería de datos desde sistemas operacionales hasta **Azure Fabric**, implementando dbt con SQL Server como plataforma de transformación local.

Aunque los datos son ficticios (AdventureWorks), la arquitectura, los patrones CDC, la protección de PII y los contratos de datos están diseñados para ser replicados directamente en producción.

---

## Arquitectura

```
AdventureWorks2016
      │  (init scripts Docker)
      ▼
dbt_cibao_raw        ← Landing Zone  (SQL Server local, Docker)
  raw_crm.*
  raw_erp.*
  raw_hr.*
      │  (dbt run)
      ▼
db_cibao_dev         ← Transformaciones dbt
  staging.*          ← Vistas: normalización 1:1 por tabla raw
  intermediate.*     ← Vistas: enriquecimiento, surrogate keys, hashes PII
  azure_fabric.*     ← Tablas incrementales: capa certificada, sin PII en claro
```

## Requisitos

- Docker Desktop
- Python 3.11+
- ODBC Driver 17 for SQL Server

```bash
# macOS
brew install microsoft/mssql-release/msodbcsql17
```

## Inicio rápido

```bash
# 1. Levantar SQL Server + cargar AdventureWorks
cd sqlserver
docker compose up -d
# Esperar ~60 segundos a que los init scripts terminen

# 2. Configurar entorno Python
cd ..
python3 -m venv .venv
source .venv/bin/activate
pip install dbt-sqlserver==1.9.0

# 3. Cargar variables de entorno y verificar conexión
source .env
dbt debug

# 4. Ejecutar transformaciones
dbt run

# 5. Correr tests
dbt test

# 6. Explorar documentación
dbt docs generate && dbt docs serve
# Abrir http://localhost:8080
```

## Estructura del proyecto

```
dbt-sqlserver-poc/
├── docs/                       # Bloques {% docs %} — documentación dbt
│   ├── _overview.md            # Visión general del proyecto (__overview__)
│   ├── _columns.md             # Docs de columnas compartidas
│   ├── _sources.md             # Docs de fuentes raw
│   ├── _staging.md             # Docs de modelos staging
│   ├── _intermediate.md        # Docs de modelos intermediate y vaults PII
│   └── _azure_fabric.md        # Docs de modelos az_ y contratos de datos
├── models/
│   ├── staging/
│   │   ├── crm/                # stg_crm__customers, stg_crm__addresses
│   │   ├── erp/                # stg_erp__order_headers, stg_erp__order_details, stg_erp__products
│   │   └── hr/                 # stg_hr__employees, stg_hr__departments
│   ├── intermediate/           # int_customers, int_employees, int_orders
│   │                           # int_pii_vault_customers, int_pii_vault_employees
│   └── azure_fabric/           # az_customers, az_addresses, az_order_headers,
│                               # az_order_details, az_products, az_employees,
│                               # az_departments, az_orders
├── sqlserver/
│   ├── docker-compose.yml      # SQL Server 2017 + Adminer
│   └── init/                   # Scripts de inicialización automática
│       ├── 01_create_databases.sql
│       ├── 02_create_tables.sql
│       └── 03_load_adventureworks.sql
├── .env                        # Credenciales locales (no subir a git)
├── dbt_project.yml
└── profiles.yml
```

## Bases de datos

| Base de datos | Propósito |
|---------------|-----------|
| `AdventureWorks2016` | Fuente de datos original (Microsoft sample) |
| `dbt_cibao_raw` | Landing zone — mirror de sistemas operacionales |
| `db_cibao_dev` | Target dbt — staging, intermediate, azure_fabric |

## Herramientas adicionales

- **Adminer** (UI web para SQL Server): http://localhost:8888
  - Sistema: MS SQL
  - Servidor: `sqlserver-cibao`
  - Usuario: `sa`
  - Contraseña: `P@ssw0rd123!`

## Documentación detallada

- [QUICKSTART.md](QUICKSTART.md) — Guía de instalación paso a paso
- [ADVENTUREWORKS_SETUP.md](ADVENTUREWORKS_SETUP.md) — Cómo funciona la carga de datos
- [AZURE_SQL_SERVER_SETUP.md](AZURE_SQL_SERVER_SETUP.md) — Configuración para apuntar a Azure Fabric
