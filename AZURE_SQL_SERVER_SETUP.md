# Azure Fabric — Configuración para producción

Este documento describe cómo apuntar el proyecto hacia un target real en Azure Fabric o Azure SQL Server, en lugar del SQL Server local de Docker.

En el PoC local, el target `dev` en `profiles.yml` apunta a `db_cibao_dev` en Docker. Para producción se cambiaría a Azure Fabric Warehouse o Azure SQL.

---

## Opción A — Azure Fabric Warehouse (recomendado para producción)

### Requisitos

- Workspace de Microsoft Fabric con un Warehouse creado
- Service Principal con rol de contribuidor en el Workspace
- `dbt-fabric` adapter instalado

```bash
pip install dbt-fabric
```

### Configurar profiles.yml

Agregar un output `prod` en `profiles.yml`:

```yaml
dbt_sqlserver_poc:
  target: dev
  outputs:
    dev:                              # target local (Docker)
      type: sqlserver
      driver: "ODBC Driver 17 for SQL Server"
      server: localhost
      port: 1433
      database: db_cibao_dev
      schema: dbo
      authentication: sql
      username: "{{ env_var('SQL_SERVER_USER', 'sa') }}"
      password: "{{ env_var('SQL_SERVER_PASSWORD') }}"
      trust_cert: true
      threads: 4

    prod:                             # target Azure Fabric
      type: fabric
      driver: "ODBC Driver 18 for SQL Server"
      server: "{{ env_var('FABRIC_SERVER') }}"
      port: 1433
      database: "{{ env_var('FABRIC_DATABASE') }}"
      schema: dbo
      authentication: ServicePrincipal
      tenant_id: "{{ env_var('AZURE_TENANT_ID') }}"
      client_id: "{{ env_var('AZURE_CLIENT_ID') }}"
      client_secret: "{{ env_var('AZURE_CLIENT_SECRET') }}"
      threads: 4
```

### Variables de entorno para producción

Agregar al `.env` (o al sistema de secretos del CI/CD):

```bash
export FABRIC_SERVER="<workspace>.datawarehouse.fabric.microsoft.com"
export FABRIC_DATABASE="<nombre-del-warehouse>"
export AZURE_TENANT_ID="<tenant-id>"
export AZURE_CLIENT_ID="<client-id>"
export AZURE_CLIENT_SECRET="<client-secret>"
```

Los valores de `AZURE_TENANT_ID`, `AZURE_CLIENT_ID` y `AZURE_CLIENT_SECRET` ya están en el `.env` del PoC como referencia.

### Ejecutar contra Fabric

```bash
source .env
dbt debug --target prod
dbt run --target prod --full-refresh   # primera carga
dbt run --target prod                   # cargas incrementales
```

---

## Opción B — Azure SQL Database

Para apuntar a una Azure SQL Database en lugar de Fabric:

```yaml
    azure_sql:
      type: sqlserver
      driver: "ODBC Driver 18 for SQL Server"
      server: "<servidor>.database.windows.net"
      port: 1433
      database: "<nombre-de-la-base>"
      schema: dbo
      authentication: ServicePrincipalCert  # o 'sql' con usuario/contraseña
      tenant_id: "{{ env_var('AZURE_TENANT_ID') }}"
      client_id: "{{ env_var('AZURE_CLIENT_ID') }}"
      client_secret: "{{ env_var('AZURE_CLIENT_SECRET') }}"
      trust_cert: true
      threads: 4
```

---

## Consideraciones al migrar a producción

### Fuentes raw

En producción, la capa `dbt_cibao_raw` la gestiona el pipeline de ingesta (ADF, Fabric Pipelines, etc.). dbt solo lee de ella como fuente — no la escribe.

Los schemas de fuentes en `models/staging/crm/_stg_crm__sources.yml`, `erp/` y `hr/` apuntan a `dbt_cibao_raw`. Si en producción la raw zone tiene otro nombre de base de datos, actualizar los campos `database:` en esos archivos o usar una variable:

```yaml
sources:
  - name: raw_crm
    database: "{{ var('raw_database', 'dbt_cibao_raw') }}"
    schema: raw_crm
```

Y pasar la variable en el run:

```bash
dbt run --target prod --vars '{"raw_database": "prod_raw_db"}'
```

### Modelos PII vault

Los modelos `int_pii_vault_*` tienen el tag `local_only` y nunca deben ejecutarse contra Azure. Excluirlos explícitamente en el pipeline de producción:

```bash
dbt run --target prod --exclude tag:local_only
```

### ODBC Driver

Azure Fabric requiere **ODBC Driver 18**. El entorno local usa ODBC Driver 17. Actualizar el campo `driver:` según corresponda.

```bash
# Instalar ODBC Driver 18 en macOS
brew install msodbcsql18
```

---

## Verificar conectividad a Azure

```bash
source .env
dbt debug --target prod
```

Si falla con error de firewall o autenticación, verificar:
1. El Service Principal tiene permisos en el Workspace de Fabric
2. El `client_secret` no está vencido
3. El servidor es accesible desde la red actual
