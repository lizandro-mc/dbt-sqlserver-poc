-- ============================================================
-- 01_create_databases.sql
-- Crea las bases de datos y schemas del landing zone
-- ============================================================

-- Landing Zone (raw data sin transformar)
CREATE DATABASE [dbt_cibao_raw]
    COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

-- Desarrollo dbt
CREATE DATABASE [db_cibao_dev]
    COLLATE SQL_Latin1_General_CP1_CI_AS;
GO

-- Simular compatibilidad SQL Server 2016 (nivel 130)
ALTER DATABASE [dbt_cibao_raw] SET COMPATIBILITY_LEVEL = 130;
GO
ALTER DATABASE [db_cibao_dev] SET COMPATIBILITY_LEVEL = 130;
GO

-- ============================================================
-- SCHEMAS EN LANDING ZONE
-- ============================================================
USE [dbt_cibao_raw];
GO

CREATE SCHEMA [raw_crm];
GO
CREATE SCHEMA [raw_erp];
GO
CREATE SCHEMA [raw_hr];
GO

-- ============================================================
-- SCHEMAS EN DEV
-- ============================================================
USE [db_cibao_dev];
GO

CREATE SCHEMA [staging];
GO
CREATE SCHEMA [intermediate];
GO
CREATE SCHEMA [marts];
GO

PRINT 'Databases and schemas created successfully.';
GO
