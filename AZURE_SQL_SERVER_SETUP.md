# 🗄️ SQL Server 2016 en Azure: Setup & Data Loading

Plan para crear SQL Server 2016 en Azure, cargar AdventureWorks, y configurarlo como landing zone operacional para dbt-gov-cibao.

---

## 📋 Arquitectura de Datos

```
Azure SQL Database (SQL Server 2016)
│
├── [dbt-cibao-raw]              ← Landing Zone (datos sin transformar)
│   ├── [raw_crm]                ← Ventas, Clientes, Contactos
│   ├── [raw_erp]                ← Productos, Órdenes, Inventario
│   ├── [raw_hr]                 ← Empleados, Departamentos
│   └── [raw_analytics]          ← Geografía, Dimensiones
│
├── [db-cibao-dev]               ← Desarrollo dbt (opcional si no usas Fabric)
│   ├── [staging]
│   ├── [intermediate]
│   └── [marts]
│
└── [AdventureWorks2016]         ← Fuente original
```

**Flujo de Datos**:
```
AdventureWorks2016 (Azure SQL)
    ↓
[dbt-cibao-raw] ← Landing zone con metadata
    ↓
dbt-fabric-poc (Fabric) ← Staging/Intermediate/Marts
    ↓
Lakehouse (Fabric)
```

---

## 🚀 PASO 1: Crear SQL Server 2016 en Azure (15-20 min)

### 1.1 Prerequisitos

- ✅ Cuenta Azure con suscripción activa
- ✅ Permisos para crear recursos (Contributor role)
- ✅ CLI de Azure instalado (opcional)

### 1.2 Opción A: Crear mediante Azure Portal (GUI)

1. **Ir a**: https://portal.azure.com
2. **Buscar**: "SQL Databases" o "SQL Servers"
3. **Click**: "+ Create" → "SQL Database"

**Configuración**:

| Campo | Valor |
|-------|-------|
| **Subscription** | Tu suscripción |
| **Resource Group** | Crear nuevo: `rg-cibao-dev` |
| **Database Name** | `sqlserver-cibao` |
| **Server** | Crear nuevo: `sqlserver-cibao-dev` |
| **Location** | East US (o tu región preferida) |
| **Compute + Storage** | Basic: 5 DTU (desarrollo) |
| **Backup** | Geo-redundant (recomendado) |

4. **Review + Create** → **Create**

⏳ Esperar 5-10 minutos a que se cree el servidor.

### 1.3 Opción B: Crear con Azure CLI

```bash
# Variables
RESOURCE_GROUP="rg-cibao-dev"
SERVER_NAME="sqlserver-cibao-dev"
DB_NAME="sqlserver-cibao"
LOCATION="eastus"
ADMIN_USER="cibaoadmin"
ADMIN_PASSWORD="P@ssw0rd123!Azure"  # ⚠️ CAMBIAR EN PRODUCCIÓN

# Crear Resource Group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Crear SQL Server
az sql server create \
  --name $SERVER_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --admin-user $ADMIN_USER \
  --admin-password $ADMIN_PASSWORD

# Crear Database
az sql db create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name $DB_NAME \
  --edition Basic \
  --capacity 5

# Crear Firewall Rule (permitir tu IP)
az sql server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name "AllowLocalIp" \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# Obtener connection string
az sql db show-connection-string \
  --server $SERVER_NAME \
  --name $DB_NAME \
  --client sqlserver
```

**Resultado esperado**:
```
sqlserver-cibao-dev.database.windows.net
```

### 1.4 Configurar Firewall para Conexiones

En Azure Portal:
1. **SQL Servers** → Tu servidor
2. **Firewalls and virtual networks**
3. **Add current client IP** o agregar tu IP manualmente

```bash
# Alternativamente, permitir acceso desde servicios Azure
az sql server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name "AllowAzureServices" \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0
```

---

## 🔐 PASO 2: Conectar a SQL Server desde Azure Data Studio

### 2.1 Instalar Azure Data Studio

```bash
# macOS
brew install azure-data-studio

# Windows
# Descargar: https://learn.microsoft.com/en-us/azure-data-studio/download-azure-data-studio

# Linux
sudo apt-get install azure-data-studio
```

### 2.2 Crear Conexión

1. **Azure Data Studio** → **Create Connection**
2. **Connection Details**:

```
Server:           sqlserver-cibao-dev.database.windows.net
Database:         sqlserver-cibao
Authentication:   SQL Login
User name:        cibaoadmin
Password:         P@ssw0rd123!Azure
Trust server cert: true
```

3. **Connect**

### 2.3 Verificar Conexión

Ejecutar en Query Editor:

```sql
SELECT 'SQL Server Connected!' as Status;
SELECT @@VERSION as SQLServerVersion;
```

---

## 📥 PASO 3: Restaurar AdventureWorks2016

### 3.1 Descargar AdventureWorks2016.bak

```bash
# Descargar desde GitHub
mkdir ~/Downloads/adventureworks
cd ~/Downloads/adventureworks

# Usando curl
curl -L -o AdventureWorks2016.bak \
  "https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2016.bak"

# Verificar descarga
ls -lh AdventureWorks2016.bak
# Expected: ~46.7 MB
```

### 3.2 Cargar .bak en Azure SQL Database

**⚠️ NOTA**: Azure SQL Database NO soporta RESTORE directo de .bak como SQL Server local.

**Alternativa**: Usar BACPAC (Azure native format)

#### Opción A: Restaurar usando Azure Portal

1. **SQL Database** → Tu DB → **Restore**
2. Seleccionar fecha de backup anterior
3. Click **Restore**

#### Opción B: Usar SQL Server Data Tools (SSDT)

Crear base de datos vacía y luego cargar datos.

#### Opción C: Usar Script SQL para Recrear Tablas (Recomendado para PoC)

Descargar scripts de creación desde:
https://github.com/Microsoft/sql-server-samples/tree/master/samples/databases/adventure-works

---

## 🛠️ PASO 4: Crear Estructura Landing Zone en Azure SQL

### 4.1 Crear Bases de Datos

Ejecutar en Azure Data Studio Query Editor:

```sql
-- ============================================
-- 1. CREAR DATABASE LANDING
-- ============================================
CREATE DATABASE [dbt_cibao_raw]
  COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

-- ============================================
-- 2. CREAR SCHEMAS EN LANDING
-- ============================================
USE [dbt_cibao_raw];
GO

CREATE SCHEMA [raw_crm];
GO
CREATE SCHEMA [raw_erp];
GO
CREATE SCHEMA [raw_hr];
GO
CREATE SCHEMA [raw_analytics];
GO

-- ============================================
-- 3. CREAR TABLAS EN LANDING CON METADATA
-- ============================================

-- CRM CUSTOMERS (from AdventureWorks Sales.Customer)
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
    [marital_status] VARCHAR(1),
    [gender] VARCHAR(1),
    [total_children] INT,
    [number_children_at_home] INT,
    [education] VARCHAR(50),
    [occupation] VARCHAR(50),
    [house_owner_flag] BIT,
    [car_owner_flag] BIT,
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'CRM',
    [_is_active] BIT DEFAULT 1,
    [_record_hash] VARCHAR(64) -- Para change detection
);
GO

-- CRM ADDRESSES
CREATE TABLE [raw_crm].[addresses] (
    [address_id] INT PRIMARY KEY,
    [customer_id] INT,
    [address_line1] VARCHAR(60),
    [address_line2] VARCHAR(60),
    [city] VARCHAR(30),
    [state_province_id] INT,
    [postal_code] VARCHAR(15),
    [country_region] VARCHAR(50),
    [address_type] VARCHAR(50),
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'CRM',
    [_is_active] BIT DEFAULT 1
);
GO

-- ERP ORDER HEADERS
CREATE TABLE [raw_erp].[order_headers] (
    [sales_order_id] INT PRIMARY KEY,
    [revision_number] TINYINT,
    [order_date] DATETIME,
    [due_date] DATETIME,
    [ship_date] DATETIME,
    [status] TINYINT,
    [online_order_flag] BIT,
    [sales_order_number] NVARCHAR(25),
    [purchase_order_number] NVARCHAR(25),
    [account_number] NVARCHAR(15),
    [customer_id] INT,
    [sales_person_id] INT,
    [territory_id] INT,
    [bill_to_address_id] INT,
    [ship_to_address_id] INT,
    [ship_method_id] INT,
    [credit_card_id] INT,
    [credit_card_approval_code] VARCHAR(15),
    [currency_rate_id] INT,
    [sub_total] NUMERIC(19, 4),
    [tax_amt] NUMERIC(19, 4),
    [freight] NUMERIC(19, 4),
    [total_due] NUMERIC(19, 4),
    [comment] NVARCHAR(MAX),
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'ERP',
    [_is_active] BIT DEFAULT 1
);
GO

-- ERP ORDER DETAILS
CREATE TABLE [raw_erp].[order_details] (
    [sales_order_id] INT,
    [sales_order_detail_id] INT,
    [carrier_tracking_number] NVARCHAR(25),
    [order_qty] SMALLINT,
    [product_id] INT,
    [special_offer_id] INT,
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

-- ERP PRODUCTS
CREATE TABLE [raw_erp].[products] (
    [product_id] INT PRIMARY KEY,
    [product_alternate_key] NVARCHAR(25),
    [product_name] NVARCHAR(50),
    [standard_cost] MONEY,
    [finish_good_flag] BIT,
    [color] NVARCHAR(15),
    [safety_stock_level] SMALLINT,
    [reorder_point] SMALLINT,
    [list_price] MONEY,
    [size] NVARCHAR(50),
    [size_unit_measure_code] NCHAR(3),
    [weight] DECIMAL(8, 2),
    [weight_unit_measure_code] NCHAR(3),
    [dw_created_date] DATETIME,
    [dw_modified_date] DATETIME,
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'ERP',
    [_is_active] BIT DEFAULT 1
);
GO

-- HR EMPLOYEES
CREATE TABLE [raw_hr].[employees] (
    [employee_id] INT PRIMARY KEY,
    [employee_alternate_key] VARCHAR(100),
    [first_name] VARCHAR(50),
    [last_name] VARCHAR(50),
    [middle_name] VARCHAR(50),
    [title] VARCHAR(100),
    [phone] VARCHAR(25),
    [email_address] VARCHAR(50),
    [hire_date] DATE,
    [birth_date] DATE,
    [job_title] VARCHAR(50),
    [department] VARCHAR(100),
    [status] VARCHAR(50),
    [current_flag] BIT,
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'HR',
    [_is_active] BIT DEFAULT 1
);
GO

-- ANALYTICS DIMENSIONS
CREATE TABLE [raw_analytics].[dim_date] (
    [date_key] INT PRIMARY KEY,
    [full_date_time_stamp] DATETIME,
    [calendar_year] INT,
    [calendar_month] INT,
    [calendar_day] INT,
    [calendar_quarter] INT,
    [day_of_week_name] VARCHAR(10),
    [english_month_name] VARCHAR(12),
    _load_ts DATETIME DEFAULT GETUTCDATE()
);
GO

CREATE TABLE [raw_analytics].[dim_geography] (
    [geography_key] INT PRIMARY KEY,
    [city] VARCHAR(30),
    [state_province_code] VARCHAR(3),
    [state_province_name] VARCHAR(50),
    [country_region_code] VARCHAR(3),
    [country_region_name] VARCHAR(50),
    [postal_code] VARCHAR(15),
    [_load_ts] DATETIME DEFAULT GETUTCDATE()
);
GO

-- Verificar tablas creadas
SELECT TABLE_SCHEMA, TABLE_NAME, COUNT(*) as RecordCount
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'dbt_cibao_raw'
GROUP BY TABLE_SCHEMA, TABLE_NAME
ORDER BY TABLE_SCHEMA;
```

---

## 📊 PASO 5: Cargar Datos desde AdventureWorks

Ejecutar en Azure Data Studio (cambiar connection a AdventureWorks2016 primero):

```sql
USE [dbt_cibao_raw];
GO

-- ============================================
-- INSERT raw_crm.customers
-- ============================================
INSERT INTO [raw_crm].[customers] (
    customer_id, person_id, store_id, territory_id,
    account_number, name, email_address, phone,
    website, annual_income, marital_status, gender,
    total_children, number_children_at_home,
    education, occupation, house_owner_flag, car_owner_flag,
    _load_ts, _load_dt, _source_system, _is_active
)
SELECT
    c.CustomerID,
    c.PersonID,
    c.StoreID,
    c.TerritoryID,
    c.AccountNumber,
    p.FirstName + ' ' + ISNULL(p.LastName, '') as name,
    ea.EmailAddress,
    pp.PhoneNumber,
    c.Website,
    dem.YearlyIncome,
    dem.MaritalStatus,
    dem.Gender,
    dem.TotalChildren,
    dem.NumberChildrenAtHome,
    dem.Education,
    dem.Occupation,
    dem.HouseOwnerFlag,
    dem.CarOwnerFlag,
    GETUTCDATE(),
    CAST(GETUTCDATE() AS DATE),
    'CRM',
    1
FROM AdventureWorks2016.Sales.Customer c
LEFT JOIN AdventureWorks2016.Person.Person p
    ON c.PersonID = p.BusinessEntityID
LEFT JOIN AdventureWorks2016.Person.EmailAddress ea
    ON p.BusinessEntityID = ea.BusinessEntityID
LEFT JOIN AdventureWorks2016.Sales.vPersonDemographics dem
    ON p.BusinessEntityID = dem.BusinessEntityID;
GO

-- ============================================
-- INSERT raw_erp.order_headers
-- ============================================
INSERT INTO [raw_erp].[order_headers]
SELECT
    SalesOrderID,
    RevisionNumber,
    OrderDate,
    DueDate,
    ShipDate,
    Status,
    OnlineOrderFlag,
    SalesOrderNumber,
    PurchaseOrderNumber,
    AccountNumber,
    CustomerID,
    SalesPersonID,
    TerritoryID,
    BillToAddressID,
    ShipToAddressID,
    ShipMethodID,
    CreditCardID,
    CreditCardApprovalCode,
    CurrencyRateID,
    SubTotal,
    TaxAmt,
    Freight,
    TotalDue,
    Comment,
    GETUTCDATE(),
    CAST(GETUTCDATE() AS DATE),
    'ERP',
    1
FROM AdventureWorks2016.Sales.SalesOrderHeader;
GO

-- ============================================
-- INSERT raw_erp.order_details
-- ============================================
INSERT INTO [raw_erp].[order_details]
SELECT
    SalesOrderID,
    SalesOrderDetailID,
    CarrierTrackingNumber,
    OrderQty,
    ProductID,
    SpecialOfferID,
    UnitPrice,
    UnitPriceDiscount,
    LineTotal,
    GETUTCDATE(),
    CAST(GETUTCDATE() AS DATE),
    'ERP',
    1
FROM AdventureWorks2016.Sales.SalesOrderDetail;
GO

-- ============================================
-- INSERT raw_erp.products
-- ============================================
INSERT INTO [raw_erp].[products]
SELECT
    ProductID,
    ProductNumber,
    Name,
    StandardCost,
    FinishedGoodsFlag,
    Color,
    SafetyStockLevel,
    ReorderPoint,
    ListPrice,
    Size,
    SizeUnitMeasureCode,
    Weight,
    WeightUnitMeasureCode,
    DueDate,
    DueDate,
    GETUTCDATE(),
    CAST(GETUTCDATE() AS DATE),
    'ERP',
    1
FROM AdventureWorks2016.Production.Product;
GO

-- ============================================
-- INSERT raw_hr.employees
-- ============================================
INSERT INTO [raw_hr].[employees]
SELECT
    BusinessEntityID,
    NationalIDNumber,
    p.FirstName,
    p.LastName,
    p.MiddleName,
    p.Title,
    pp.PhoneNumber,
    ea.EmailAddress,
    e.HireDate,
    e.BirthDate,
    e.JobTitle,
    'Human Resources',
    e.CurrentFlag,
    e.CurrentFlag,
    GETUTCDATE(),
    CAST(GETUTCDATE() AS DATE),
    'HR',
    1
FROM AdventureWorks2016.HumanResources.Employee e
LEFT JOIN AdventureWorks2016.Person.Person p
    ON e.BusinessEntityID = p.BusinessEntityID
LEFT JOIN AdventureWorks2016.Person.EmailAddress ea
    ON p.BusinessEntityID = ea.BusinessEntityID
LEFT JOIN AdventureWorks2016.Person.PersonPhone pp
    ON p.BusinessEntityID = pp.BusinessEntityID;
GO

-- ============================================
-- VERIFY DATA LOADED
-- ============================================
SELECT 'raw_crm.customers' as [Table], COUNT(*) as [RecordCount]
FROM [raw_crm].[customers]
UNION ALL
SELECT 'raw_erp.order_headers', COUNT(*)
FROM [raw_erp].[order_headers]
UNION ALL
SELECT 'raw_erp.order_details', COUNT(*)
FROM [raw_erp].[order_details]
UNION ALL
SELECT 'raw_erp.products', COUNT(*)
FROM [raw_erp].[products]
UNION ALL
SELECT 'raw_hr.employees', COUNT(*)
FROM [raw_hr].[employees];
GO
```

---

## 🔗 PASO 6: Configurar Conexión en dbt-fabric-poc

### 6.1 Actualizar profiles.yml

```yaml
# ~/.dbt/profiles.yml

dbt_fabric_poc:
  target: dev
  outputs:
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

    # ✨ NUEVO: Conexión a SQL Server para landing zone
    sql_server_dev:
      type: sqlserver
      driver: "ODBC Driver 18 for SQL Server"
      server: sqlserver-cibao-dev.database.windows.net
      port: 1433
      database: dbt_cibao_raw
      schema: dbo
      authentication: sql
      username: "{{ env_var('SQL_SERVER_USER') }}"
      password: "{{ env_var('SQL_SERVER_PASSWORD') }}"
      threads: 4
```

### 6.2 Actualizar _sources.yml

Agregar fuentes de SQL Server:

```yaml
# models/staging/_sources.yml

version: 2

sources:
  # ============================================
  # FUENTES LANDING ZONE (SQL Server Azure)
  # ============================================
  - name: raw_crm
    database: dbt_cibao_raw
    schema: raw_crm
    description: "Raw CRM data from SQL Server"
    tables:
      - name: customers
        columns:
          - name: customer_id
            tests: [unique, not_null]

  - name: raw_erp
    database: dbt_cibao_raw
    schema: raw_erp
    description: "Raw ERP data from SQL Server"
    tables:
      - name: order_headers
        columns:
          - name: sales_order_id
            tests: [unique, not_null]

  # ============================================
  # FUENTES EXISTING (Fabric)
  # ============================================
  - name: adventureworks
    database: "{{ env_var('DBT_SOURCE_DATABASE', 'lh_dev') }}"
    schema: dbo
    # ... resto de configuración
```

### 6.3 Probar Conexión

```bash
# En la raíz de dbt-fabric-poc
cd /Users/lizandro/code/dbt-fabric-poc

# Exportar credenciales SQL Server
export SQL_SERVER_USER="cibaoadmin"
export SQL_SERVER_PASSWORD="P@ssw0rd123!Azure"

# Test de conexión (usando sql_server_dev target)
dbt debug --target sql_server_dev

# Expected:
#   Connection test: [ok] took 0.08s
```

---

## 📊 Resumen: Datos en Azure SQL

Después de completar todos los pasos:

| Database | Schema | Table | Records |
|----------|--------|-------|---------|
| dbt_cibao_raw | raw_crm | customers | ~19,000 |
| dbt_cibao_raw | raw_crm | addresses | ~19,000 |
| dbt_cibao_raw | raw_erp | order_headers | ~31,000 |
| dbt_cibao_raw | raw_erp | order_details | ~121,000 |
| dbt_cibao_raw | raw_erp | products | ~504 |
| dbt_cibao_raw | raw_hr | employees | ~290 |

**Total**: ~191,000 registros

---

## 🔄 Próximos Pasos

1. ✅ SQL Server 2016 en Azure creado
2. ✅ Base de datos dbt_cibao_raw con landing schemas
3. ✅ Datos de AdventureWorks cargados
4. ✅ Conexión en dbt-fabric-poc configurada
5. → **Siguiente**: Crear modelos dbt que lean desde landing zone
6. → **Después**: Transformar datos en Fabric

---

## 🚨 Troubleshooting

### Error: "Server not found"
```bash
# Verificar nombre del servidor
az sql server show --name sqlserver-cibao-dev --resource-group rg-cibao-dev
```

### Error: "Firewall blocked"
```bash
# Agregar IP actual
az sql server firewall-rule create \
  --resource-group rg-cibao-dev \
  --server sqlserver-cibao-dev \
  --name "AllowMyIp" \
  --start-ip-address YOUR_IP \
  --end-ip-address YOUR_IP
```

### Error: "Cannot restore .bak to Azure SQL"
→ Usar script SQL para recrear tablas (como en PASO 4 y 5)

---

## 💰 Costos Estimados (Monthly)

| Recurso | Tier | Costo |
|---------|------|-------|
| SQL Server | Azure SQL, 5 DTU | ~$15-20 |
| Storage | 5 GB | ~$1 |
| **Total** | | ~$16-21/mes |

(Variar según región y tier elegido)

---

## 📚 Referencias

- **Azure SQL Database**: https://learn.microsoft.com/en-us/azure/azure-sql/
- **SQL Server on Azure**: https://learn.microsoft.com/en-us/sql/
- **AdventureWorks Scripts**: https://github.com/Microsoft/sql-server-samples
