# Instalación y Setup de AdventureWorks2016

## 📥 Paso 1: Descargar AdventureWorks2016

### Opción A: Descargar .bak desde GitHub (Recomendado)

```bash
# Ir a la carpeta de descargas
cd ~/Downloads

# Descargar AdventureWorks2016.bak (46.7 MB)
# https://github.com/Microsoft/sql-server-samples/releases/tag/adventureworks
# Click en "AdventureWorks2016.bak" para descargar

# Alternativamente, con wget si está disponible:
wget -O AdventureWorks2016.bak \
  "https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2016.bak"
```

### Opción B: Usar Script de Instalación T-SQL

```bash
# Descargar y extraer scripts
wget -O adventureworks-scripts.zip \
  "https://github.com/Microsoft/sql-server-samples/archive/refs/heads/master.zip"

# Extraer y navegar
unzip adventureworks-scripts.zip
cd sql-server-samples-master/samples/databases/adventure-works/
```

---

## 🗄️ Paso 2: Restaurar en SQL Server 2016

### Método A: Usando SQL Server Management Studio (SSMS)

1. **Abrir SSMS** → Conectar a SQL Server 2016
2. **Right-click en Databases** → **Restore Database**
3. **Device** → Seleccionar `AdventureWorks2016.bak`
4. **Destination Database**: `AdventureWorks2016`
5. **Options**:
   - Recovery state: `RECOVER`
   - Replace existing database: ☑️
6. **Click OK** (esperar 30-60 segundos)

### Método B: Usando T-SQL

```sql
-- Restaurar desde archivo .bak
USE master;
GO

RESTORE DATABASE AdventureWorks2016
  FROM DISK = 'C:\Users\YourUser\Downloads\AdventureWorks2016.bak'
  WITH
    MOVE 'AdventureWorks2016_data'
      TO 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\AdventureWorks2016.mdf',
    MOVE 'AdventureWorks2016_Log'
      TO 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\LOG\AdventureWorks2016_log.ldf',
    REPLACE,
    RECOVERY;
GO

-- Verificar instalación
SELECT name, state_desc FROM sys.databases WHERE name = 'AdventureWorks2016';
```

---

## ✅ Paso 3: Verificar Instalación

```sql
-- Contar tablas
SELECT COUNT(*) as TableCount
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'AdventureWorks2016'
  AND TABLE_TYPE = 'BASE TABLE';
-- Expected: 71 tablas

-- Ver esquemas
SELECT DISTINCT TABLE_SCHEMA
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'AdventureWorks2016'
ORDER BY TABLE_SCHEMA;
-- Expected: 6 esquemas (dbo, HumanResources, Person, Production, Purchasing, Sales)

-- Ver data sample (primeros registros)
SELECT TOP 5 * FROM Sales.Customer;
SELECT TOP 5 * FROM Sales.SalesOrderHeader;
SELECT TOP 5 * FROM Production.Product;
```

---

## 🎯 Paso 4: Crear Bases de Datos Landing y dbt

### 4.1 Crear Estructura Landing en SQL Server

```sql
-- ============================================
-- CREATE LANDING/RAW DATABASE
-- ============================================
CREATE DATABASE [dbt-cibao-raw]
  CONTAINMENT = NONE
  ON PRIMARY
    (NAME = N'dbt-cibao-raw', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\dbt-cibao-raw.mdf')
  LOG ON
    (NAME = N'dbt-cibao-raw_log', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\LOG\dbt-cibao-raw_log.ldf');
GO

-- ============================================
-- CREATE DEVELOPMENT DATABASE
-- ============================================
CREATE DATABASE [db-cibao-dev]
  CONTAINMENT = NONE
  ON PRIMARY
    (NAME = N'db-cibao-dev', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\db-cibao-dev.mdf')
  LOG ON
    (NAME = N'db-cibao-dev_log', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\LOG\db-cibao-dev_log.ldf');
GO

-- ============================================
-- CREATE PRODUCTION DATABASE
-- ============================================
CREATE DATABASE [db-cibao-prod]
  CONTAINMENT = NONE
  ON PRIMARY
    (NAME = N'db-cibao-prod', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA\db-cibao-prod.mdf')
  LOG ON
    (NAME = N'db-cibao-prod_log', FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\LOG\db-cibao-prod_log.ldf');
GO

-- ============================================
-- CREATE SCHEMAS IN LANDING
-- ============================================
USE [dbt-cibao-raw];
GO

CREATE SCHEMA [raw_crm];
GO
CREATE SCHEMA [raw_erp];
GO
CREATE SCHEMA [raw_hr];
GO
CREATE SCHEMA [raw_api_payments];
GO

-- ============================================
-- CREATE SCHEMAS IN DEV & PROD
-- ============================================
USE [db-cibao-dev];
GO
CREATE SCHEMA [staging];
GO
CREATE SCHEMA [intermediate];
GO
CREATE SCHEMA [marts];
GO

USE [db-cibao-prod];
GO
CREATE SCHEMA [staging];
GO
CREATE SCHEMA [intermediate];
GO
CREATE SCHEMA [marts];
GO
```

### 4.2 Crear Tablas Landing desde AdventureWorks

```sql
-- ============================================
-- COPY RAW_CRM TABLES (simular CRM)
-- ============================================
USE [dbt-cibao-raw];
GO

-- raw_crm.customers (from Sales.Customer)
CREATE TABLE [raw_crm].[customers] (
    [customer_id] INT PRIMARY KEY,
    [person_id] INT,
    [store_id] INT,
    [territory_id] INT,
    [account_number] VARCHAR(10),
    [name] VARCHAR(255),        -- Denormalizado para simular CRM
    [email_address] VARCHAR(50),
    [phone] VARCHAR(25),
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'CRM',
    [_is_active] BIT DEFAULT 1
);
GO

-- raw_crm.addresses (from Person.Address)
CREATE TABLE [raw_crm].[addresses] (
    [address_id] INT PRIMARY KEY,
    [address_line1] VARCHAR(60),
    [address_line2] VARCHAR(60),
    [city] VARCHAR(30),
    [state_province_id] INT,
    [postal_code] VARCHAR(15),
    [country_region] VARCHAR(50),
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'CRM',
    [_is_active] BIT DEFAULT 1
);
GO

-- ============================================
-- COPY RAW_ERP TABLES (simular ERP)
-- ============================================

-- raw_erp.order_headers (from Sales.SalesOrderHeader)
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

-- raw_erp.order_details (from Sales.SalesOrderDetail)
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

-- raw_erp.products (from Production.Product)
CREATE TABLE [raw_erp].[products] (
    [product_id] INT PRIMARY KEY,
    [name] NVARCHAR(50),
    [product_number] NVARCHAR(25),
    [make_flag] BIT,
    [finished_goods_flag] BIT,
    [color] NVARCHAR(15),
    [safety_stock_level] SMALLINT,
    [reorder_point] SMALLINT,
    [standard_cost] NUMERIC(19, 4),
    [list_price] NUMERIC(19, 4),
    [size] NVARCHAR(5),
    [weight] DECIMAL(8, 2),
    [product_category_id] INT,
    [product_subcategory_id] INT,
    [sell_start_date] DATETIME,
    [sell_end_date] DATETIME,
    [discontinued_date] DATETIME,
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'ERP',
    [_is_active] BIT DEFAULT 1
);
GO

-- ============================================
-- COPY RAW_HR TABLES (simular HR)
-- ============================================

-- raw_hr.employees (from HumanResources.Employee)
CREATE TABLE [raw_hr].[employees] (
    [business_entity_id] INT PRIMARY KEY,
    [national_id_number] NVARCHAR(15),
    [login_id] NVARCHAR(256),
    [organizational_level] SMALLINT,
    [job_title] NVARCHAR(50),
    [birth_date] DATE,
    [marital_status] NCHAR(1),
    [gender] NCHAR(1),
    [hire_date] DATE,
    [salaried_flag] BIT,
    [vacation_hours] SMALLINT,
    [sick_leave_hours] SMALLINT,
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'HR',
    [_is_active] BIT DEFAULT 1
);
GO

-- raw_hr.departments (from HumanResources.Department)
CREATE TABLE [raw_hr].[departments] (
    [department_id] SMALLINT PRIMARY KEY,
    [name] NVARCHAR(50),
    [group_name] NVARCHAR(50),
    [modify_date] DATETIME,
    [_load_ts] DATETIME DEFAULT GETUTCDATE(),
    [_load_dt] DATE DEFAULT CAST(GETUTCDATE() AS DATE),
    [_source_system] VARCHAR(50) DEFAULT 'HR',
    [_is_active] BIT DEFAULT 1
);
GO

-- ============================================
-- POPULATE TABLES FROM ADVENTUREWORKS
-- ============================================

-- Llenar raw_crm.customers
INSERT INTO [dbt-cibao-raw].[raw_crm].[customers]
SELECT
  c.CustomerID,
  c.PersonID,
  c.StoreID,
  c.TerritoryID,
  c.AccountNumber,
  p.FirstName + ' ' + ISNULL(p.LastName, ''),
  ea.EmailAddress,
  pp.PhoneNumber,
  GETUTCDATE(),
  CAST(GETUTCDATE() AS DATE),
  'CRM',
  1
FROM AdventureWorks2016.Sales.Customer c
  LEFT JOIN AdventureWorks2016.Person.Person p ON c.PersonID = p.BusinessEntityID
  LEFT JOIN AdventureWorks2016.Person.EmailAddress ea ON p.BusinessEntityID = ea.BusinessEntityID
  LEFT JOIN AdventureWorks2016.Person.PersonPhone pp ON p.BusinessEntityID = pp.BusinessEntityID;
GO

-- Llenar raw_erp.order_headers
INSERT INTO [dbt-cibao-raw].[raw_erp].[order_headers]
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

-- Llenar raw_erp.order_details
INSERT INTO [dbt-cibao-raw].[raw_erp].[order_details]
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

-- Llenar raw_erp.products
INSERT INTO [dbt-cibao-raw].[raw_erp].[products]
SELECT
  ProductID,
  Name,
  ProductNumber,
  MakeFlag,
  FinishedGoodsFlag,
  Color,
  SafetyStockLevel,
  ReorderPoint,
  StandardCost,
  ListPrice,
  Size,
  Weight,
  ProductCategoryID,
  ProductSubcategoryID,
  SellStartDate,
  SellEndDate,
  DiscontinuedDate,
  GETUTCDATE(),
  CAST(GETUTCDATE() AS DATE),
  'ERP',
  1
FROM AdventureWorks2016.Production.Product;
GO

-- Llenar raw_hr.employees
INSERT INTO [dbt-cibao-raw].[raw_hr].[employees]
SELECT
  BusinessEntityID,
  NationalIDNumber,
  LoginID,
  OrganizationLevel,
  JobTitle,
  BirthDate,
  MaritalStatus,
  Gender,
  HireDate,
  SalariedFlag,
  VacationHours,
  SickLeaveHours,
  GETUTCDATE(),
  CAST(GETUTCDATE() AS DATE),
  'HR',
  1
FROM AdventureWorks2016.HumanResources.Employee;
GO

-- ============================================
-- VERIFY DATA LOADED
-- ============================================

SELECT 'raw_crm.customers' as [Table], COUNT(*) as [RecordCount]
FROM [dbt-cibao-raw].[raw_crm].[customers]
UNION ALL
SELECT 'raw_erp.order_headers', COUNT(*)
FROM [dbt-cibao-raw].[raw_erp].[order_headers]
UNION ALL
SELECT 'raw_erp.order_details', COUNT(*)
FROM [dbt-cibao-raw].[raw_erp].[order_details]
UNION ALL
SELECT 'raw_erp.products', COUNT(*)
FROM [dbt-cibao-raw].[raw_erp].[products]
UNION ALL
SELECT 'raw_hr.employees', COUNT(*)
FROM [dbt-cibao-raw].[raw_hr].[employees];
GO
```

---

## 📊 Paso 5: Resumen de Datos

Después de completar la instalación, deberías tener:

| Database | Schema | Table | Records |
|----------|--------|-------|---------|
| dbt-cibao-raw | raw_crm | customers | ~19,000 |
| dbt-cibao-raw | raw_crm | addresses | ~19,000 |
| dbt-cibao-raw | raw_erp | order_headers | ~31,000 |
| dbt-cibao-raw | raw_erp | order_details | ~121,000 |
| dbt-cibao-raw | raw_erp | products | ~504 |
| dbt-cibao-raw | raw_hr | employees | ~290 |
| dbt-cibao-raw | raw_hr | departments | ~16 |

**Total: ~191,000 registros** para testing

---

## 🔗 Próximos Pasos

1. ✅ Completar instalación de SQL Server con dbt-cibao-raw/dev/prod
2. → Crear repositorio dbt-gov-cibao
3. → Configurar conexión SQL Server en profiles.yml
4. → Crear modelos staging
