# Quickstart — dbt SQL Server PoC

Guía completa para levantar el entorno local desde cero.

---

## Requisitos previos

| Herramienta | Versión mínima | Instalación |
|-------------|---------------|-------------|
| Docker Desktop | 4.x | https://www.docker.com/products/docker-desktop |
| Python | 3.11+ | https://www.python.org/downloads |
| ODBC Driver 17 | — | ver abajo |
| Git | — | https://git-scm.com |

### Instalar ODBC Driver 17

```bash
# macOS
brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
brew install msodbcsql17

# Ubuntu / Debian
curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list > /etc/apt/sources.list.d/mssql-release.list
apt-get update && ACCEPT_EULA=Y apt-get install msodbcsql17
```

---

## Paso 1 — Clonar el repositorio

```bash
git clone <url-del-repo>
cd dbt-sqlserver-poc
```

---

## Paso 2 — Levantar SQL Server con Docker

```bash
cd sqlserver
docker compose up -d
```

Esto levanta:
- **SQL Server 2017** en `localhost:1433` (compatibilidad level 130 = SQL Server 2016)
- **Adminer** en `http://localhost:8888` — UI web para explorar las tablas

Al arrancar por primera vez, Docker ejecuta automáticamente los init scripts:

1. `01_create_databases.sql` — Crea `dbt_cibao_raw` y `db_cibao_dev`
2. `02_create_tables.sql` — Crea las tablas raw con metadata de pipeline
3. `03_load_adventureworks.sql` — Carga datos de AdventureWorks2016

Este proceso tarda aproximadamente **60-90 segundos**. Verificar que el healthcheck esté en verde:

```bash
docker ps
# NAMES             STATUS
# sqlserver-cibao   Up X minutes (healthy)
```

Para ver los logs de inicialización:

```bash
docker logs sqlserver-cibao 2>&1 | grep -E "Batch|rows affected|Error"
```

---

## Paso 3 — Entorno Python

```bash
cd ..   # volver a la raíz del proyecto

python3 -m venv .venv
source .venv/bin/activate        # macOS/Linux
# .venv\Scripts\activate         # Windows

pip install dbt-sqlserver==1.9.0
```

Verificar la instalación:

```bash
dbt --version
# Core:     1.11.7
# Plugins:  sqlserver: 1.9.0
```

---

## Paso 4 — Variables de entorno

El archivo `.env` ya existe con las credenciales del Docker local:

```bash
cat .env
```

Para cargar las variables en la sesión actual:

```bash
source .env
```

> Agregar `source .env` a tu `.zshrc` o `.bashrc` si quieres que se carguen automáticamente, o ejecutarlo cada vez que abras una nueva terminal.

---

## Paso 5 — Verificar conexión dbt

```bash
source .venv/bin/activate
source .env
dbt debug
```

Output esperado:
```
Connection test: [OK]
All checks passed!
```

---

## Paso 6 — Ejecutar los modelos

Primera ejecución (full load):

```bash
dbt run --full-refresh
```

Ejecuciones posteriores (incremental — solo procesa cambios):

```bash
dbt run
```

Output esperado:
```
20 of 20 OK  ...
Completed successfully
```

Ejecutar solo una capa:

```bash
dbt run --select staging
dbt run --select intermediate
dbt run --select azure_fabric
```

---

## Paso 7 — Correr los tests

```bash
dbt test
```

Los tests incluyen `not_null`, `unique`, `relationships` y `accepted_values` para todas las capas. Los tests sobre modelos `az_` tienen `contract_status: visado`.

---

## Paso 8 — Explorar la documentación

```bash
dbt docs generate
dbt docs serve
```

Abrir `http://localhost:8080` para:
- Leer el overview completo del proyecto
- Explorar el linaje de modelos (grafo de dependencias)
- Ver los contratos de datos de cada modelo
- Consultar la estrategia de PII y el patrón CDC

---

## Comandos frecuentes

```bash
# Correr un modelo específico y sus dependencias upstream
dbt run --select +az_customers

# Correr un modelo y sus dependencias downstream
dbt run --select az_customers+

# Solo tests de un modelo
dbt test --select az_customers

# Ver el SQL compilado de un modelo
dbt compile --select int_customers
cat target/compiled/dbt_sqlserver_poc/models/intermediate/int_customers.sql

# Limpiar artifacts compilados
dbt clean
```

---

## Verificar datos en SQL Server

Con Adminer en http://localhost:8888:
- Sistema: **MS SQL**
- Servidor: `sqlserver-cibao`
- Usuario: `sa`
- Contraseña: `P@ssw0rd123!`
- Base de datos: `db_cibao_dev`

O con sqlcmd desde terminal:

```bash
source .env
sqlcmd -S localhost,1433 -U sa -P "$SQL_SERVER_PASSWORD" \
  -Q "SELECT schema_name, COUNT(*) as tables FROM db_cibao_dev.INFORMATION_SCHEMA.TABLES GROUP BY schema_name"
```

---

## Reiniciar el entorno desde cero

Si necesitas resetear todo (borrar datos y volver a inicializar):

```bash
cd sqlserver
docker compose down -v          # borra contenedores Y volúmenes
docker compose up -d            # recrea todo desde cero
```

> El flag `-v` elimina el volumen `sqlserver_cibao_data`. Sin él, Docker reutiliza los datos existentes y no ejecuta los init scripts nuevamente.

---

## Troubleshooting

**Login failed for user 'sa'**
```bash
# Verificar que las variables están exportadas correctamente
source .env
python3 -c "import os; print(os.environ.get('SQL_SERVER_PASSWORD', 'NOT SET'))"
# Debe imprimir la contraseña, no 'NOT SET'
```

**Container no llega a estado healthy**
```bash
docker logs sqlserver-cibao 2>&1 | tail -30
# Revisar si hay errores de SQL en los init scripts
```

**ODBC Driver not found**
```bash
odbcinst -q -d | grep -i sql
# Debe mostrar: [ODBC Driver 17 for SQL Server]
# Si no aparece, reinstalar msodbcsql17
```

**dbt: Database not found**
```bash
# Verificar que los init scripts se ejecutaron
source .env
sqlcmd -S localhost,1433 -U sa -P "$SQL_SERVER_PASSWORD" \
  -Q "SELECT name FROM sys.databases"
# Debe incluir: dbt_cibao_raw y db_cibao_dev
```
