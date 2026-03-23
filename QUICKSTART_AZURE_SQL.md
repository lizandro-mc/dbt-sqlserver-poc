# 🚀 Quick Start: SQL Server 2016 en Azure + dbt-fabric-poc

Plan de acción inmediato para configurar data operacional en Azure SQL y conectarla a dbt.

---

## ⏱️ Timeline: ~45 minutos

| Paso | Tiempo | Acción |
|------|--------|--------|
| 1 | 5 min | Crear SQL Server en Azure |
| 2 | 10 min | Cargar datos AdventureWorks |
| 3 | 15 min | Crear landing zone schemas |
| 4 | 10 min | Configurar dbt profiles |
| 5 | 5 min | Test conexión dbt |

---

## 📋 PASO 1: Crear SQL Server (5 min)

### Opción Rápida: Azure CLI

Copiar y ejecutar en terminal:

```bash
#!/bin/bash

# Variables
RESOURCE_GROUP="rg-cibao-dev"
SERVER_NAME="sqlserver-cibao-dev"
DB_NAME="cibao-data"
LOCATION="eastus"
ADMIN_USER="cibaoadmin"
ADMIN_PASSWORD="CibaoPoC2024!"

# Crear Resource Group
echo "📁 Creando Resource Group..."
az group create --name $RESOURCE_GROUP --location $LOCATION

# Crear SQL Server
echo "🗄️  Creando SQL Server..."
az sql server create \
  --name $SERVER_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --admin-user $ADMIN_USER \
  --admin-password $ADMIN_PASSWORD \
  --enable-ad-only-auth false

# Crear Database
echo "📊 Creando Database..."
az sql db create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name $DB_NAME \
  --edition Basic \
  --capacity 5 \
  --collation SQL_Latin1_General_CP1_CI_AS

# Firewall: Permitir acceso desde servicios Azure
echo "🔐 Configurando Firewall..."
az sql server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name "AllowAzureServices" \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# Obtener connection string
echo ""
echo "✅ SQL Server creado exitosamente!"
echo ""
az sql db show-connection-string \
  --server $SERVER_NAME \
  --name $DB_NAME \
  --client sqlserver
```

**Resultado esperado:**
```
sqlserver-cibao-dev.database.windows.net
```

Guarda estos datos:
- **Server**: `sqlserver-cibao-dev.database.windows.net`
- **Username**: `cibaoadmin`
- **Password**: `CibaoPoC2024!`
- **Database**: `cibao-data`

---

## 📥 PASO 2: Cargar Datos AdventureWorks (10 min)

### 2.1 Instalar Azure Data Studio (si no lo tienes)

```bash
# macOS
brew install azure-data-studio

# Windows: https://learn.microsoft.com/en-us/azure-data-studio/download-azure-data-studio
```

### 2.2 Conectar a SQL Server

1. Abrir **Azure Data Studio**
2. **Create Connection**
3. Pegar credenciales:

```
Server:           sqlserver-cibao-dev.database.windows.net
Database:         cibao-data
Authentication:   SQL Login
User name:        cibaoadmin
Password:         CibaoPoC2024!
Trust server cert: true
```

4. **Connect**

### 2.3 Ejecutar Script de Creación

En Azure Data Studio, New Query → Copiar y ejecutar TODO este script:

```sql
-- ============================================
-- CREAR SCHEMAS LANDING ZONE
-- ============================================
CREATE SCHEMA [raw_crm];
GO
CREATE SCHEMA [raw_erp];
GO
CREATE SCHEMA [raw_hr];
GO
CREATE SCHEMA [raw_analytics];
GO

-- ============================================
-- CREAR TABLA: raw_crm.customers
-- ============================================
CREATE TABLE [raw_crm].[customers] (
    [customer_id] INT PRIMARY KEY,
    [person_id] INT,
    [store_id] INT,
    [territory_id] INT,
    [account_number] VARCHAR(10),
    [name] VARCHAR(255),
    [email_address] VARCHAR(50),
    [phone] VARCHAR(25),
    [website] VARCHAR(255),
    [annual_income] VARCHAR(100),
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'CRM',
    [_is_active] BIT DEFAULT 1
);
GO

-- ============================================
-- CREAR TABLA: raw_erp.order_headers
-- ============================================
CREATE TABLE [raw_erp].[order_headers] (
    [sales_order_id] INT PRIMARY KEY,
    [revision_number] TINYINT,
    [order_date] DATETIME,
    [due_date] DATETIME,
    [ship_date] DATETIME,
    [status] TINYINT,
    [customer_id] INT,
    [sales_person_id] INT,
    [territory_id] INT,
    [sub_total] NUMERIC(19, 4),
    [tax_amt] NUMERIC(19, 4),
    [freight] NUMERIC(19, 4),
    [total_due] NUMERIC(19, 4),
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'ERP',
    [_is_active] BIT DEFAULT 1
);
GO

-- ============================================
-- CREAR TABLA: raw_erp.order_details
-- ============================================
CREATE TABLE [raw_erp].[order_details] (
    [sales_order_id] INT,
    [sales_order_detail_id] INT,
    [order_qty] SMALLINT,
    [product_id] INT,
    [unit_price] NUMERIC(19, 4),
    [unit_price_discount] NUMERIC(19, 4),
    [line_total] NUMERIC(19, 4),
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'ERP',
    [_is_active] BIT DEFAULT 1,
    PRIMARY KEY ([sales_order_id], [sales_order_detail_id])
);
GO

-- ============================================
-- CREAR TABLA: raw_erp.products
-- ============================================
CREATE TABLE [raw_erp].[products] (
    [product_id] INT PRIMARY KEY,
    [product_name] NVARCHAR(50),
    [standard_cost] MONEY,
    [list_price] MONEY,
    [size] NVARCHAR(50),
    [weight] DECIMAL(8, 2),
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'ERP',
    [_is_active] BIT DEFAULT 1
);
GO

-- ============================================
-- CREAR TABLA: raw_hr.employees
-- ============================================
CREATE TABLE [raw_hr].[employees] (
    [employee_id] INT PRIMARY KEY,
    [first_name] VARCHAR(50),
    [last_name] VARCHAR(50),
    [email_address] VARCHAR(50),
    [job_title] VARCHAR(50),
    [hire_date] DATE,
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'HR',
    [_is_active] BIT DEFAULT 1
);
GO

-- Verificar
SELECT 'OK - Schemas y tablas creadas' as Status;
```

---

## 📥 PASO 3: Cargar Datos desde AdventureWorks (15 min)

### 3.1 Conectar a AdventureWorks

Si tienes AdventureWorks en local o en Azure, usar Azure Data Studio para conectar.

Si no tienes acceso a AdventureWorks, puedes:
1. Descargar el script desde: https://github.com/Microsoft/sql-server-samples/tree/master/samples/databases/adventure-works/oltp-install-script
2. O cargar datos de prueba generados

### 3.2 Script de Carga (si tienes AdventureWorks disponible)

```sql
-- Asumiendo que tienes AdventureWorks en el mismo servidor

-- Cargar clientes
INSERT INTO [dbo].[raw_crm].[customers]
SELECT
    c.CustomerID,
    c.PersonID,
    c.StoreID,
    c.TerritoryID,
    c.AccountNumber,
    ISNULL(p.FirstName + ' ' + p.LastName, 'Unknown') as name,
    ea.EmailAddress,
    pp.PhoneNumber,
    c.Website,
    dem.YearlyIncome,
    GETUTCDATE(),
    CAST(GETUTCDATE() AS DATE),
    'CRM',
    1
FROM AdventureWorks2016.Sales.Customer c
LEFT JOIN AdventureWorks2016.Person.Person p ON c.PersonID = p.BusinessEntityID
LEFT JOIN AdventureWorks2016.Person.EmailAddress ea ON p.BusinessEntityID = ea.BusinessEntityID
LEFT JOIN AdventureWorks2016.Person.PersonPhone pp ON p.BusinessEntityID = pp.BusinessEntityID
LEFT JOIN AdventureWorks2016.Sales.vPersonDemographics dem ON p.BusinessEntityID = dem.BusinessEntityID;
GO

-- Cargar órdenes
INSERT INTO [dbo].[raw_erp].[order_headers]
SELECT
    SalesOrderID,
    RevisionNumber,
    OrderDate,
    DueDate,
    ShipDate,
    Status,
    CustomerID,
    SalesPersonID,
    TerritoryID,
    SubTotal,
    TaxAmt,
    Freight,
    TotalDue,
    GETUTCDATE(),
    CAST(GETUTCDATE() AS DATE),
    'ERP',
    1
FROM AdventureWorks2016.Sales.SalesOrderHeader;
GO

-- Cargar detalles de órdenes
INSERT INTO [dbo].[raw_erp].[order_details]
SELECT
    SalesOrderID,
    SalesOrderDetailID,
    OrderQty,
    ProductID,
    UnitPrice,
    UnitPriceDiscount,
    LineTotal,
    GETUTCDATE(),
    CAST(GETUTCDATE() AS DATE),
    'ERP',
    1
FROM AdventureWorks2016.Sales.SalesOrderDetail;
GO

-- Cargar productos
INSERT INTO [dbo].[raw_erp].[products]
SELECT
    ProductID,
    Name,
    StandardCost,
    ListPrice,
    Size,
    Weight,
    GETUTCDATE(),
    CAST(GETUTCDATE() AS DATE),
    'ERP',
    1
FROM AdventureWorks2016.Production.Product;
GO

-- Verificar carga
SELECT 'raw_crm.customers' as [Table], COUNT(*) as [RecordCount]
FROM [dbo].[raw_crm].[customers]
UNION ALL
SELECT 'raw_erp.order_headers', COUNT(*)
FROM [dbo].[raw_erp].[order_headers]
UNION ALL
SELECT 'raw_erp.order_details', COUNT(*)
FROM [dbo].[raw_erp].[order_details]
UNION ALL
SELECT 'raw_erp.products', COUNT(*)
FROM [dbo].[raw_erp].[products];
```

### 3.2 Alternativa: Cargar Datos de Prueba (sin AdventureWorks)

Si no tienes acceso a AdventureWorks, ejecutar este script para datos de prueba:

```sql
-- Datos de prueba: Clientes
INSERT INTO [dbo].[raw_crm].[customers] (
    customer_id, person_id, store_id, territory_id,
    account_number, name, email_address, phone,
    _load_ts, _load_dt, _source_system, _is_active
)
VALUES
    (1, 1, 1, 1, 'ACC001', 'John Smith', 'john@example.com', '555-0001', GETUTCDATE(), CAST(GETUTCDATE() AS DATE), 'CRM', 1),
    (2, 2, 1, 1, 'ACC002', 'Jane Doe', 'jane@example.com', '555-0002', GETUTCDATE(), CAST(GETUTCDATE() AS DATE), 'CRM', 1),
    (3, 3, 2, 2, 'ACC003', 'Bob Wilson', 'bob@example.com', '555-0003', GETUTCDATE(), CAST(GETUTCDATE() AS DATE), 'CRM', 1),
    (4, 4, 2, 2, 'ACC004', 'Alice Brown', 'alice@example.com', '555-0004', GETUTCDATE(), CAST(GETUTCDATE() AS DATE), 'CRM', 1),
    (5, 5, 3, 3, 'ACC005', 'Charlie Davis', 'charlie@example.com', '555-0005', GETUTCDATE(), CAST(GETUTCDATE() AS DATE), 'CRM', 1);
GO

-- Datos de prueba: Órdenes
INSERT INTO [dbo].[raw_erp].[order_headers] (
    sales_order_id, order_date, customer_id, sub_total, tax_amt, freight, total_due,
    _load_ts, _load_dt, _source_system, _is_active
)
VALUES
    (1, '2024-01-15', 1, 1000.00, 100.00, 50.00, 1150.00, GETUTCDATE(), CAST(GETUTCDATE() AS DATE), 'ERP', 1),
    (2, '2024-01-16', 2, 2000.00, 200.00, 75.00, 2275.00, GETUTCDATE(), CAST(GETUTCDATE() AS DATE), 'ERP', 1),
    (3, '2024-01-17', 3, 1500.00, 150.00, 60.00, 1710.00, GETUTCDATE(), CAST(GETUTCDATE() AS DATE), 'ERP', 1);
GO

-- Datos de prueba: Productos
INSERT INTO [dbo].[raw_erp].[products] (
    product_id, product_name, standard_cost, list_price,
    _load_ts, _load_dt, _source_system, _is_active
)
VALUES
    (1, 'Product A', 100.00, 150.00, GETUTCDATE(), CAST(GETUTCDATE() AS DATE), 'ERP', 1),
    (2, 'Product B', 200.00, 300.00, GETUTCDATE(), CAST(GETUTCDATE() AS DATE), 'ERP', 1),
    (3, 'Product C', 150.00, 250.00, GETUTCDATE(), CAST(GETUTCDATE() AS DATE), 'ERP', 1);
GO

SELECT 'Test data loaded successfully' as Status;
```

---

## 🔗 PASO 4: Configurar dbt Profiles (10 min)

### 4.1 Actualizar ~/.dbt/profiles.yml

Abrir editor:

```bash
nano ~/.dbt/profiles.yml
```

Agregar esta configuración (debajo de la existente):

```yaml
dbt_fabric_poc:
  target: dev
  outputs:
    # ============================================
    # FABRIC (existente)
    # ============================================
    dev:
      type: fabric
      driver: "ODBC Driver 18 for SQL Server"
      server: mq2rj3ebaxnu3htglwggzbzqdu-nhpo5gv3ievuzo2wtw4mwpbzvm.datawarehouse.fabric.microsoft.com
      port: 1433
      database: wh_dev
      schema: dbo
      authentication: ServicePrincipal
      tenant_id: "{{ env_var('AZURE_TENANT_ID') }}"
      client_id: "{{ env_var('AZURE_CLIENT_ID') }}"
      client_secret: "{{ env_var('AZURE_CLIENT_SECRET') }}"
      threads: 4

    # ============================================
    # SQL SERVER - LANDING ZONE (nuevo)
    # ============================================
    sql_server_landing:
      type: sqlserver
      driver: "ODBC Driver 18 for SQL Server"
      server: sqlserver-cibao-dev.database.windows.net
      port: 1433
      database: cibao-data
      schema: dbo
      authentication: sql
      username: "{{ env_var('SQL_SERVER_USER', 'cibaoadmin') }}"
      password: "{{ env_var('SQL_SERVER_PASSWORD') }}"
      threads: 4
```

Guardar: `Ctrl+X` → `Y` → `Enter`

### 4.2 Exportar Variables de Entorno

```bash
# En terminal, exportar credenciales SQL Server
export SQL_SERVER_USER="cibaoadmin"
export SQL_SERVER_PASSWORD="CibaoPoC2024!"

# Verificar (should echo your password)
echo $SQL_SERVER_PASSWORD
```

Para hacerlo permanente, agregar a `~/.zshrc` o `~/.bashrc`:

```bash
echo "export SQL_SERVER_USER='cibaoadmin'" >> ~/.zshrc
echo "export SQL_SERVER_PASSWORD='CibaoPoC2024!'" >> ~/.zshrc
source ~/.zshrc
```

---

## ✅ PASO 5: Test Conexión dbt (5 min)

```bash
# Ir al proyecto dbt
cd /Users/lizandro/code/dbt-fabric-poc

# Test de conexión a SQL Server
dbt debug --target sql_server_landing

# Expected output:
#   Connection test: [ok] took X.XXs
#   All checks passed!
```

Si falla, revisar:

```bash
# Verificar credenciales
echo "User: $SQL_SERVER_USER"
echo "Password: $SQL_SERVER_PASSWORD"

# Verificar driver ODBC
isql -l | grep "ODBC"

# Si no aparece "ODBC Driver 18 for SQL Server", instalar:
# macOS:
brew install odbc-sqlserver
```

---

## 📊 Verificar Datos en SQL

```sql
-- En Azure Data Studio, ejecutar:

SELECT 'Landing Zone Summary' as Report;
GO

SELECT TABLE_NAME, COUNT(*) as RecordCount
FROM INFORMATION_SCHEMA.TABLES t
LEFT JOIN (SELECT * FROM [raw_crm].[customers]) c ON 1=1
LEFT JOIN (SELECT * FROM [raw_erp].[order_headers]) oh ON 1=1
GROUP BY TABLE_NAME;

-- O simplemente:
SELECT COUNT(*) as TotalRecords FROM [raw_crm].[customers];
SELECT COUNT(*) as TotalRecords FROM [raw_erp].[order_headers];
```

---

## 🎯 Resumen: ¿Qué Tenemos Ahora?

✅ **SQL Server 2016 en Azure** con:
- Base de datos: `cibao-data`
- Schemas: `raw_crm`, `raw_erp`, `raw_hr`, `raw_analytics`
- Tablas: customers, order_headers, order_details, products
- Datos operacionales cargados
- Metadata columns (_load_ts, _load_dt, _source_system, _is_active)

✅ **dbt-fabric-poc** configurado para:
- Leer desde SQL Server (`sql_server_landing` target)
- Transformar en Fabric (`dev` target)

---

## 🚀 Próximos Pasos

1. Crear modelos dbt que lean desde `raw_crm`, `raw_erp`
2. Implementar transformaciones en Fabric
3. Crear marts finales para consumo

**Documento siguiente**: `DBT_MODELS_LANDING_TO_FABRIC.md` (crear nueva guía)

---

## 🆘 Troubleshooting Rápido

| Error | Solución |
|-------|----------|
| "Connection refused" | Verificar firewall en Azure (Allow Azure Services) |
| "Authentication failed" | Verificar usuario/password en env vars |
| "ODBC Driver not found" | Instalar: `brew install odbc-sqlserver` |
| "Database not found" | Verificar que cibao-data existe |
| "Table doesn't exist" | Ejecutar script SQL nuevamente (Paso 3) |

---

## 💬 Comandos Útiles

```bash
# Ver bases de datos
az sql db list --server sqlserver-cibao-dev --resource-group rg-cibao-dev

# Ver firewall rules
az sql server firewall-rule list --server sqlserver-cibao-dev --resource-group rg-cibao-dev

# Eliminar (si es necesario)
az group delete --name rg-cibao-dev --yes --no-wait
```

---

¡Listo! Ejecuta el script de PASO 1 ahora y en 45 minutos tendrás todo configurado. 🚀
