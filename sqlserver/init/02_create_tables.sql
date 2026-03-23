-- ============================================================
-- 02_create_tables.sql
-- Landing zone tables con metadata obligatoria según estándar
-- Modern Data Stack (lizandro-mc.github.io/modern-data-stack)
--
-- Metadata obligatoria por registro:
--   _ingested_at   → timestamp UTC de carga
--   _source_system → sistema origen en minúsculas (crm, erp, hr)
--   _source_entity → tabla/entidad de origen
--   _pipeline_name → nombre del pipeline que cargó
--   _batch_id      → UUID de la ejecución (agrupa todos los registros de una carga)
--   _raw_hash      → SHA-256 del registro completo (change detection)
--   _is_deleted    → bandera CDC para registros eliminados en origen
-- ============================================================

USE [dbt_cibao_raw];
GO

-- ============================================================
-- RAW_CRM — Simula sistema CRM (AdventureWorks Sales + Person)
-- ============================================================

CREATE TABLE [raw_crm].[customers] (
    -- payload
    [customer_id]        INT            NOT NULL,
    [person_id]          INT,
    [store_id]           INT,
    [territory_id]       INT,
    [account_number]     VARCHAR(10),
    [name]               VARCHAR(255),
    [email_address]      VARCHAR(50),
    [phone]              VARCHAR(25),
    -- metadata obligatoria
    [_ingested_at]       DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    [_source_system]     VARCHAR(50)    NOT NULL DEFAULT 'crm',
    [_source_entity]     VARCHAR(100)   NOT NULL DEFAULT 'customers',
    [_pipeline_name]     VARCHAR(200)   NOT NULL DEFAULT 'pl_load_crm_customers_full',
    [_batch_id]          VARCHAR(36)    NOT NULL DEFAULT NEWID(),
    [_raw_hash]          VARCHAR(64),
    [_is_deleted]        BIT            NOT NULL DEFAULT 0,
    CONSTRAINT pk_raw_crm_customers PRIMARY KEY ([customer_id])
);
GO

CREATE TABLE [raw_crm].[addresses] (
    -- payload
    [address_id]         INT            NOT NULL,
    [customer_id]        INT,
    [address_line1]      VARCHAR(60),
    [address_line2]      VARCHAR(60),
    [city]               VARCHAR(30),
    [state_province_id]  INT,
    [postal_code]        VARCHAR(15),
    [country_region]     VARCHAR(50),
    -- metadata obligatoria
    [_ingested_at]       DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    [_source_system]     VARCHAR(50)    NOT NULL DEFAULT 'crm',
    [_source_entity]     VARCHAR(100)   NOT NULL DEFAULT 'addresses',
    [_pipeline_name]     VARCHAR(200)   NOT NULL DEFAULT 'pl_load_crm_addresses_full',
    [_batch_id]          VARCHAR(36)    NOT NULL DEFAULT NEWID(),
    [_raw_hash]          VARCHAR(64),
    [_is_deleted]        BIT            NOT NULL DEFAULT 0,
    CONSTRAINT pk_raw_crm_addresses PRIMARY KEY ([address_id])
);
GO

-- ============================================================
-- RAW_ERP — Simula sistema ERP (AdventureWorks Sales + Production)
-- ============================================================

CREATE TABLE [raw_erp].[order_headers] (
    -- payload
    [sales_order_id]           INT            NOT NULL,
    [revision_number]          TINYINT,
    [order_date]               DATETIME,
    [due_date]                 DATETIME,
    [ship_date]                DATETIME,
    [status]                   TINYINT,
    [online_order_flag]        BIT,
    [sales_order_number]       NVARCHAR(25),
    [purchase_order_number]    NVARCHAR(25),
    [account_number]           NVARCHAR(15),
    [customer_id]              INT,
    [sales_person_id]          INT,
    [territory_id]             INT,
    [sub_total]                NUMERIC(19,4),
    [tax_amt]                  NUMERIC(19,4),
    [freight]                  NUMERIC(19,4),
    [total_due]                NUMERIC(19,4),
    -- metadata obligatoria
    [_ingested_at]             DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    [_source_system]           VARCHAR(50)    NOT NULL DEFAULT 'erp',
    [_source_entity]           VARCHAR(100)   NOT NULL DEFAULT 'order_headers',
    [_pipeline_name]           VARCHAR(200)   NOT NULL DEFAULT 'pl_load_erp_order_headers_full',
    [_batch_id]                VARCHAR(36)    NOT NULL DEFAULT NEWID(),
    [_raw_hash]                VARCHAR(64),
    [_is_deleted]              BIT            NOT NULL DEFAULT 0,
    CONSTRAINT pk_raw_erp_order_headers PRIMARY KEY ([sales_order_id])
);
GO

CREATE TABLE [raw_erp].[order_details] (
    -- payload
    [sales_order_id]           INT            NOT NULL,
    [sales_order_detail_id]    INT            NOT NULL,
    [carrier_tracking_number]  NVARCHAR(25),
    [order_qty]                SMALLINT,
    [product_id]               INT,
    [special_offer_id]         INT,
    [unit_price]               NUMERIC(19,4),
    [unit_price_discount]      NUMERIC(19,4),
    [line_total]               NUMERIC(19,4),
    -- metadata obligatoria
    [_ingested_at]             DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    [_source_system]           VARCHAR(50)    NOT NULL DEFAULT 'erp',
    [_source_entity]           VARCHAR(100)   NOT NULL DEFAULT 'order_details',
    [_pipeline_name]           VARCHAR(200)   NOT NULL DEFAULT 'pl_load_erp_order_details_full',
    [_batch_id]                VARCHAR(36)    NOT NULL DEFAULT NEWID(),
    [_raw_hash]                VARCHAR(64),
    [_is_deleted]              BIT            NOT NULL DEFAULT 0,
    CONSTRAINT pk_raw_erp_order_details PRIMARY KEY ([sales_order_id], [sales_order_detail_id])
);
GO

CREATE TABLE [raw_erp].[products] (
    -- payload
    [product_id]               INT            NOT NULL,
    [product_number]           NVARCHAR(25),
    [product_name]             NVARCHAR(50),
    [standard_cost]            NUMERIC(19,4),
    [list_price]               NUMERIC(19,4),
    [finished_goods_flag]      BIT,
    [color]                    NVARCHAR(15),
    [safety_stock_level]       SMALLINT,
    [reorder_point]            SMALLINT,
    [size]                     NVARCHAR(50),
    [weight]                   DECIMAL(8,2),
    -- metadata obligatoria
    [_ingested_at]             DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    [_source_system]           VARCHAR(50)    NOT NULL DEFAULT 'erp',
    [_source_entity]           VARCHAR(100)   NOT NULL DEFAULT 'products',
    [_pipeline_name]           VARCHAR(200)   NOT NULL DEFAULT 'pl_load_erp_products_full',
    [_batch_id]                VARCHAR(36)    NOT NULL DEFAULT NEWID(),
    [_raw_hash]                VARCHAR(64),
    [_is_deleted]              BIT            NOT NULL DEFAULT 0,
    CONSTRAINT pk_raw_erp_products PRIMARY KEY ([product_id])
);
GO

-- ============================================================
-- RAW_HR — Simula sistema HR (AdventureWorks HumanResources)
-- ============================================================

CREATE TABLE [raw_hr].[employees] (
    -- payload
    [business_entity_id]       INT            NOT NULL,
    [national_id_number]       NVARCHAR(15),
    [login_id]                 NVARCHAR(256),
    [job_title]                NVARCHAR(50),
    [birth_date]               DATE,
    [marital_status]           NCHAR(1),
    [gender]                   NCHAR(1),
    [hire_date]                DATE,
    [salaried_flag]            BIT,
    [vacation_hours]           SMALLINT,
    [sick_leave_hours]         SMALLINT,
    -- metadata obligatoria
    [_ingested_at]             DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    [_source_system]           VARCHAR(50)    NOT NULL DEFAULT 'hr',
    [_source_entity]           VARCHAR(100)   NOT NULL DEFAULT 'employees',
    [_pipeline_name]           VARCHAR(200)   NOT NULL DEFAULT 'pl_load_hr_employees_full',
    [_batch_id]                VARCHAR(36)    NOT NULL DEFAULT NEWID(),
    [_raw_hash]                VARCHAR(64),
    [_is_deleted]              BIT            NOT NULL DEFAULT 0,
    CONSTRAINT pk_raw_hr_employees PRIMARY KEY ([business_entity_id])
);
GO

CREATE TABLE [raw_hr].[departments] (
    -- payload
    [department_id]            SMALLINT       NOT NULL,
    [name]                     NVARCHAR(50),
    [group_name]               NVARCHAR(50),
    -- metadata obligatoria
    [_ingested_at]             DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    [_source_system]           VARCHAR(50)    NOT NULL DEFAULT 'hr',
    [_source_entity]           VARCHAR(100)   NOT NULL DEFAULT 'departments',
    [_pipeline_name]           VARCHAR(200)   NOT NULL DEFAULT 'pl_load_hr_departments_full',
    [_batch_id]                VARCHAR(36)    NOT NULL DEFAULT NEWID(),
    [_raw_hash]                VARCHAR(64),
    [_is_deleted]              BIT            NOT NULL DEFAULT 0,
    CONSTRAINT pk_raw_hr_departments PRIMARY KEY ([department_id])
);
GO

PRINT 'Landing zone tables created with standard metadata columns.';
GO
