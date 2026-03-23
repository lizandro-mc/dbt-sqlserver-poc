# AdventureWorks — Carga de datos

Describe cómo funciona la inicialización automática de datos en el entorno Docker local.

---

## Cómo funciona

Al ejecutar `docker compose up -d` por primera vez, SQL Server monta el directorio `sqlserver/init/` y ejecuta los scripts `.sql` en orden alfabético. Estos scripts solo se ejecutan cuando el volumen está vacío (primera vez o después de `docker compose down -v`).

```
sqlserver/
└── init/
    ├── 01_create_databases.sql   ← Bases de datos y schemas
    ├── 02_create_tables.sql      ← Tablas raw con metadata de pipeline
    └── 03_load_adventureworks.sql ← Carga datos desde AdventureWorks2016
```

---

## Qué crean los scripts

### 01_create_databases.sql

Crea dos bases de datos en SQL Server:

| Base de datos | Propósito |
|---------------|-----------|
| `dbt_cibao_raw` | Landing zone — datos raw con metadata de ingesta |
| `db_cibao_dev` | Target dbt — staging, intermediate, azure_fabric |

Ambas quedan con `COMPATIBILITY_LEVEL = 130` (equivalente a SQL Server 2016).

Schemas creados en `dbt_cibao_raw`:
- `raw_crm` — datos del sistema CRM (clientes, direcciones)
- `raw_erp` — datos del sistema ERP (órdenes, productos)
- `raw_hr` — datos del sistema RRHH (empleados, departamentos)

### 02_create_tables.sql

Crea las tablas del landing zone con el estándar de metadata de pipeline:

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `_ingested_at` | DATETIME2 | Timestamp UTC de la carga |
| `_source_system` | VARCHAR(50) | Sistema origen (crm, erp, hr) |
| `_source_entity` | VARCHAR(100) | Nombre de la tabla fuente |
| `_pipeline_name` | VARCHAR(100) | Nombre del proceso de carga |
| `_batch_id` | VARCHAR(36) | UUID que agrupa todos los registros de una carga |
| `_raw_hash` | VARCHAR(64) | SHA-256 de los campos de negocio — usado para CDC |
| `_is_deleted` | BIT | Flag de borrado lógico (1 = eliminado en la fuente) |

Tablas creadas:

```
dbt_cibao_raw
├── raw_crm.customers
├── raw_crm.addresses
├── raw_erp.order_headers
├── raw_erp.order_details
├── raw_erp.products
├── raw_hr.employees
└── raw_hr.departments
```

### 03_load_adventureworks.sql

Carga datos desde `AdventureWorks2016` (que viene preinstalada en el contenedor) hacia el landing zone, aplicando:

- `MERGE` idempotente — se puede ejecutar varias veces sin duplicar datos
- `_batch_id` único por ejecución (`NEWID()`)
- `_raw_hash` calculado con SHA2_256 de todos los campos de negocio
- `_is_deleted = 0` en la carga inicial

Volumen de datos aproximado después de la carga:

| Tabla | Registros |
|-------|-----------|
| `raw_crm.customers` | ~19,000 |
| `raw_crm.addresses` | ~19,000 |
| `raw_erp.order_headers` | ~31,000 |
| `raw_erp.order_details` | ~121,000 |
| `raw_erp.products` | ~504 |
| `raw_hr.employees` | ~290 |
| `raw_hr.departments` | ~16 |

---

## Verificar que la carga completó

```bash
source .env

# Ver los batch_id de cada carga (debe haber exactamente 1 por tabla en carga inicial)
sqlcmd -S localhost,1433 -U sa -P "$SQL_SERVER_PASSWORD" -d dbt_cibao_raw \
  -Q "SELECT _source_entity, COUNT(*) as rows, MIN(_ingested_at) as loaded_at
      FROM raw_crm.customers
      GROUP BY _source_entity"
```

O desde Adminer en http://localhost:8888.

---

## Reinicializar desde cero

Si los datos están corruptos o quieres volver a un estado limpio:

```bash
cd sqlserver

# Parar y eliminar contenedores + volumen de datos
docker compose down -v

# Volver a levantar (ejecuta los init scripts de nuevo)
docker compose up -d

# Seguir los logs de inicialización
docker logs -f sqlserver-cibao 2>&1 | grep -E "Batch|rows affected|PRINT|Error"
```

> Sin el flag `-v`, Docker reutiliza el volumen existente y los init scripts NO se vuelven a ejecutar.

---

## Ejecutar un script manualmente

Si necesitas correr uno de los scripts sin recrear el contenedor:

```bash
source .env

docker exec -i sqlserver-cibao \
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$SQL_SERVER_PASSWORD" \
  -i /init/03_load_adventureworks.sql
```

---

## Diferencia con el entorno de producción

En producción, la capa raw no se carga con scripts init de Docker sino con un pipeline de ingesta (ADF, Fabric Data Factory, o similar) que:

- Hace TRUNCATE + full reload en cada ejecución
- Calcula `_raw_hash` y `_batch_id` automáticamente
- Marca `_is_deleted = 1` para registros eliminados en la fuente

Los init scripts de este PoC simulan el resultado final de ese pipeline con los mismos metadatos y estructura de columnas.
