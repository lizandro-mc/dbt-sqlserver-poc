-- ============================================================
-- 03_load_adventureworks.sql
-- Carga datos de AdventureWorks2016 en el landing zone
--
-- Estándares aplicados (modern-data-stack):
--   - Idempotencia: MERGE evita duplicados en re-ejecuciones
--   - _batch_id único por ejecución (agrupa toda la carga)
--   - _raw_hash SHA-256 para change detection
--   - _is_deleted = 0 en carga full (CDC vendría después)
--   - Carga por sistema fuente en schema separado
-- ============================================================

USE [dbt_cibao_raw];
GO

-- Batch ID único para esta ejecución (agrupa todos los registros)
DECLARE @batch_id   VARCHAR(36)  = CONVERT(VARCHAR(36), NEWID());
DECLARE @ingested_at DATETIME2(0) = SYSUTCDATETIME();

PRINT 'Batch ID: ' + @batch_id;
PRINT 'Ingested at: ' + CONVERT(VARCHAR, @ingested_at, 126);
PRINT '-----------------------------------------------------';

-- ============================================================
-- raw_crm.customers
-- Fuente: AdventureWorks2016.Sales.Customer + Person
-- Idempotente: MERGE por customer_id
-- ============================================================
PRINT 'Loading raw_crm.customers...';

MERGE [raw_crm].[customers] AS target
USING (
    SELECT
        c.CustomerID                                       AS customer_id,
        c.PersonID                                         AS person_id,
        c.StoreID                                          AS store_id,
        c.TerritoryID                                      AS territory_id,
        c.AccountNumber                                    AS account_number,
        ISNULL(p.FirstName + ' ' + p.LastName, 'Unknown') AS name,
        ea.EmailAddress                                    AS email_address,
        pp.PhoneNumber                                     AS phone,
        CONVERT(VARCHAR(64),
            HASHBYTES('SHA2_256',
                CONCAT(
                    ISNULL(CAST(c.CustomerID AS VARCHAR), ''),  '|',
                    ISNULL(c.AccountNumber, ''),                '|',
                    ISNULL(p.FirstName + ' ' + p.LastName, ''), '|',
                    ISNULL(ea.EmailAddress, ''),                '|',
                    ISNULL(pp.PhoneNumber, '')
                )
            ), 2
        )                                                  AS _raw_hash
    FROM AdventureWorks2016.Sales.Customer c
    LEFT JOIN AdventureWorks2016.Person.Person p
        ON c.PersonID = p.BusinessEntityID
    LEFT JOIN AdventureWorks2016.Person.EmailAddress ea
        ON p.BusinessEntityID = ea.BusinessEntityID
    LEFT JOIN AdventureWorks2016.Person.PersonPhone pp
        ON p.BusinessEntityID = pp.BusinessEntityID
) AS source ON target.[customer_id] = source.[customer_id]
WHEN MATCHED AND target.[_raw_hash] <> source.[_raw_hash] THEN
    UPDATE SET
        target.[person_id]      = source.[person_id],
        target.[store_id]       = source.[store_id],
        target.[territory_id]   = source.[territory_id],
        target.[account_number] = source.[account_number],
        target.[name]           = source.[name],
        target.[email_address]  = source.[email_address],
        target.[phone]          = source.[phone],
        target.[_ingested_at]   = @ingested_at,
        target.[_batch_id]      = @batch_id,
        target.[_raw_hash]      = source.[_raw_hash],
        target.[_is_deleted]    = 0
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        [customer_id], [person_id], [store_id], [territory_id],
        [account_number], [name], [email_address], [phone],
        [_ingested_at], [_source_system], [_source_entity],
        [_pipeline_name], [_batch_id], [_raw_hash], [_is_deleted]
    )
    VALUES (
        source.[customer_id], source.[person_id], source.[store_id], source.[territory_id],
        source.[account_number], source.[name], source.[email_address], source.[phone],
        @ingested_at, 'crm', 'customers',
        'pl_load_crm_customers_full', @batch_id, source.[_raw_hash], 0
    );

PRINT '  -> raw_crm.customers: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows affected';
GO

-- ============================================================
-- raw_crm.addresses
-- Fuente: AdventureWorks2016.Person.Address
-- ============================================================
DECLARE @batch_id    VARCHAR(36)  = CONVERT(VARCHAR(36), NEWID());
DECLARE @ingested_at DATETIME2(0) = SYSUTCDATETIME();

PRINT 'Loading raw_crm.addresses...';

MERGE [raw_crm].[addresses] AS target
USING (
    SELECT
        a.AddressID                                        AS address_id,
        ca.BusinessEntityID                                AS customer_id,
        a.AddressLine1                                     AS address_line1,
        a.AddressLine2                                     AS address_line2,
        a.City                                             AS city,
        a.StateProvinceID                                  AS state_province_id,
        a.PostalCode                                       AS postal_code,
        cr.Name                                            AS country_region,
        CONVERT(VARCHAR(64),
            HASHBYTES('SHA2_256',
                CONCAT(
                    ISNULL(CAST(a.AddressID AS VARCHAR), ''), '|',
                    ISNULL(a.AddressLine1, ''),               '|',
                    ISNULL(a.City, ''),                       '|',
                    ISNULL(a.PostalCode, '')
                )
            ), 2
        )                                                  AS _raw_hash
    FROM AdventureWorks2016.Person.Address a
    LEFT JOIN AdventureWorks2016.Person.BusinessEntityAddress ca
        ON a.AddressID = ca.AddressID AND ca.BusinessEntityID IN (
            SELECT CustomerID FROM AdventureWorks2016.Sales.Customer
        )
    LEFT JOIN AdventureWorks2016.Person.StateProvince sp
        ON a.StateProvinceID = sp.StateProvinceID
    LEFT JOIN AdventureWorks2016.Person.CountryRegion cr
        ON sp.CountryRegionCode = cr.CountryRegionCode
) AS source ON target.[address_id] = source.[address_id]
WHEN MATCHED AND target.[_raw_hash] <> source.[_raw_hash] THEN
    UPDATE SET
        target.[customer_id]      = source.[customer_id],
        target.[address_line1]    = source.[address_line1],
        target.[address_line2]    = source.[address_line2],
        target.[city]             = source.[city],
        target.[state_province_id]= source.[state_province_id],
        target.[postal_code]      = source.[postal_code],
        target.[country_region]   = source.[country_region],
        target.[_ingested_at]     = @ingested_at,
        target.[_batch_id]        = @batch_id,
        target.[_raw_hash]        = source.[_raw_hash],
        target.[_is_deleted]      = 0
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        [address_id], [customer_id], [address_line1], [address_line2],
        [city], [state_province_id], [postal_code], [country_region],
        [_ingested_at], [_source_system], [_source_entity],
        [_pipeline_name], [_batch_id], [_raw_hash], [_is_deleted]
    )
    VALUES (
        source.[address_id], source.[customer_id], source.[address_line1], source.[address_line2],
        source.[city], source.[state_province_id], source.[postal_code], source.[country_region],
        @ingested_at, 'crm', 'addresses',
        'pl_load_crm_addresses_full', @batch_id, source.[_raw_hash], 0
    );

PRINT '  -> raw_crm.addresses: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows affected';
GO

-- ============================================================
-- raw_erp.order_headers
-- Fuente: AdventureWorks2016.Sales.SalesOrderHeader
-- ============================================================
DECLARE @batch_id    VARCHAR(36)  = CONVERT(VARCHAR(36), NEWID());
DECLARE @ingested_at DATETIME2(0) = SYSUTCDATETIME();

PRINT 'Loading raw_erp.order_headers...';

MERGE [raw_erp].[order_headers] AS target
USING (
    SELECT
        SalesOrderID                AS sales_order_id,
        RevisionNumber              AS revision_number,
        OrderDate                   AS order_date,
        DueDate                     AS due_date,
        ShipDate                    AS ship_date,
        Status                      AS status,
        OnlineOrderFlag             AS online_order_flag,
        SalesOrderNumber            AS sales_order_number,
        PurchaseOrderNumber         AS purchase_order_number,
        AccountNumber               AS account_number,
        CustomerID                  AS customer_id,
        SalesPersonID               AS sales_person_id,
        TerritoryID                 AS territory_id,
        SubTotal                    AS sub_total,
        TaxAmt                      AS tax_amt,
        Freight                     AS freight,
        TotalDue                    AS total_due,
        CONVERT(VARCHAR(64),
            HASHBYTES('SHA2_256',
                CONCAT(
                    CAST(SalesOrderID AS VARCHAR),      '|',
                    CAST(RevisionNumber AS VARCHAR),    '|',
                    CAST(Status AS VARCHAR),            '|',
                    ISNULL(CAST(TotalDue AS VARCHAR), '')
                )
            ), 2
        )                           AS _raw_hash
    FROM AdventureWorks2016.Sales.SalesOrderHeader
) AS source ON target.[sales_order_id] = source.[sales_order_id]
WHEN MATCHED AND target.[_raw_hash] <> source.[_raw_hash] THEN
    UPDATE SET
        target.[revision_number]        = source.[revision_number],
        target.[status]                 = source.[status],
        target.[ship_date]              = source.[ship_date],
        target.[sub_total]              = source.[sub_total],
        target.[tax_amt]                = source.[tax_amt],
        target.[freight]                = source.[freight],
        target.[total_due]              = source.[total_due],
        target.[_ingested_at]           = @ingested_at,
        target.[_batch_id]              = @batch_id,
        target.[_raw_hash]              = source.[_raw_hash],
        target.[_is_deleted]            = 0
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        [sales_order_id], [revision_number], [order_date], [due_date], [ship_date],
        [status], [online_order_flag], [sales_order_number], [purchase_order_number],
        [account_number], [customer_id], [sales_person_id], [territory_id],
        [sub_total], [tax_amt], [freight], [total_due],
        [_ingested_at], [_source_system], [_source_entity],
        [_pipeline_name], [_batch_id], [_raw_hash], [_is_deleted]
    )
    VALUES (
        source.[sales_order_id], source.[revision_number], source.[order_date], source.[due_date], source.[ship_date],
        source.[status], source.[online_order_flag], source.[sales_order_number], source.[purchase_order_number],
        source.[account_number], source.[customer_id], source.[sales_person_id], source.[territory_id],
        source.[sub_total], source.[tax_amt], source.[freight], source.[total_due],
        @ingested_at, 'erp', 'order_headers',
        'pl_load_erp_order_headers_full', @batch_id, source.[_raw_hash], 0
    );

PRINT '  -> raw_erp.order_headers: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows affected';
GO

-- ============================================================
-- raw_erp.order_details
-- Fuente: AdventureWorks2016.Sales.SalesOrderDetail
-- ============================================================
DECLARE @batch_id    VARCHAR(36)  = CONVERT(VARCHAR(36), NEWID());
DECLARE @ingested_at DATETIME2(0) = SYSUTCDATETIME();

PRINT 'Loading raw_erp.order_details...';

MERGE [raw_erp].[order_details] AS target
USING (
    SELECT
        SalesOrderID                AS sales_order_id,
        SalesOrderDetailID          AS sales_order_detail_id,
        CarrierTrackingNumber       AS carrier_tracking_number,
        OrderQty                    AS order_qty,
        ProductID                   AS product_id,
        SpecialOfferID              AS special_offer_id,
        UnitPrice                   AS unit_price,
        UnitPriceDiscount           AS unit_price_discount,
        LineTotal                   AS line_total,
        CONVERT(VARCHAR(64),
            HASHBYTES('SHA2_256',
                CONCAT(
                    CAST(SalesOrderID AS VARCHAR),       '|',
                    CAST(SalesOrderDetailID AS VARCHAR), '|',
                    CAST(OrderQty AS VARCHAR),           '|',
                    ISNULL(CAST(LineTotal AS VARCHAR), '')
                )
            ), 2
        )                           AS _raw_hash
    FROM AdventureWorks2016.Sales.SalesOrderDetail
) AS source
ON target.[sales_order_id]        = source.[sales_order_id]
AND target.[sales_order_detail_id] = source.[sales_order_detail_id]
WHEN MATCHED AND target.[_raw_hash] <> source.[_raw_hash] THEN
    UPDATE SET
        target.[order_qty]             = source.[order_qty],
        target.[unit_price]            = source.[unit_price],
        target.[unit_price_discount]   = source.[unit_price_discount],
        target.[line_total]            = source.[line_total],
        target.[_ingested_at]          = @ingested_at,
        target.[_batch_id]             = @batch_id,
        target.[_raw_hash]             = source.[_raw_hash],
        target.[_is_deleted]           = 0
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        [sales_order_id], [sales_order_detail_id], [carrier_tracking_number],
        [order_qty], [product_id], [special_offer_id],
        [unit_price], [unit_price_discount], [line_total],
        [_ingested_at], [_source_system], [_source_entity],
        [_pipeline_name], [_batch_id], [_raw_hash], [_is_deleted]
    )
    VALUES (
        source.[sales_order_id], source.[sales_order_detail_id], source.[carrier_tracking_number],
        source.[order_qty], source.[product_id], source.[special_offer_id],
        source.[unit_price], source.[unit_price_discount], source.[line_total],
        @ingested_at, 'erp', 'order_details',
        'pl_load_erp_order_details_full', @batch_id, source.[_raw_hash], 0
    );

PRINT '  -> raw_erp.order_details: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows affected';
GO

-- ============================================================
-- raw_erp.products
-- Fuente: AdventureWorks2016.Production.Product
-- ============================================================
DECLARE @batch_id    VARCHAR(36)  = CONVERT(VARCHAR(36), NEWID());
DECLARE @ingested_at DATETIME2(0) = SYSUTCDATETIME();

PRINT 'Loading raw_erp.products...';

MERGE [raw_erp].[products] AS target
USING (
    SELECT
        ProductID                   AS product_id,
        ProductNumber               AS product_number,
        Name                        AS product_name,
        StandardCost                AS standard_cost,
        ListPrice                   AS list_price,
        FinishedGoodsFlag           AS finished_goods_flag,
        Color                       AS color,
        SafetyStockLevel            AS safety_stock_level,
        ReorderPoint                AS reorder_point,
        Size                        AS size,
        Weight                      AS weight,
        CONVERT(VARCHAR(64),
            HASHBYTES('SHA2_256',
                CONCAT(
                    CAST(ProductID AS VARCHAR),                     '|',
                    ISNULL(ProductNumber, ''),                      '|',
                    ISNULL(Name, ''),                               '|',
                    ISNULL(CAST(StandardCost AS VARCHAR), ''),      '|',
                    ISNULL(CAST(ListPrice AS VARCHAR), '')
                )
            ), 2
        )                           AS _raw_hash
    FROM AdventureWorks2016.Production.Product
) AS source ON target.[product_id] = source.[product_id]
WHEN MATCHED AND target.[_raw_hash] <> source.[_raw_hash] THEN
    UPDATE SET
        target.[product_number]    = source.[product_number],
        target.[product_name]      = source.[product_name],
        target.[standard_cost]     = source.[standard_cost],
        target.[list_price]        = source.[list_price],
        target.[color]             = source.[color],
        target.[_ingested_at]      = @ingested_at,
        target.[_batch_id]         = @batch_id,
        target.[_raw_hash]         = source.[_raw_hash],
        target.[_is_deleted]       = 0
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        [product_id], [product_number], [product_name],
        [standard_cost], [list_price], [finished_goods_flag],
        [color], [safety_stock_level], [reorder_point], [size], [weight],
        [_ingested_at], [_source_system], [_source_entity],
        [_pipeline_name], [_batch_id], [_raw_hash], [_is_deleted]
    )
    VALUES (
        source.[product_id], source.[product_number], source.[product_name],
        source.[standard_cost], source.[list_price], source.[finished_goods_flag],
        source.[color], source.[safety_stock_level], source.[reorder_point], source.[size], source.[weight],
        @ingested_at, 'erp', 'products',
        'pl_load_erp_products_full', @batch_id, source.[_raw_hash], 0
    );

PRINT '  -> raw_erp.products: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows affected';
GO

-- ============================================================
-- raw_hr.employees
-- Fuente: AdventureWorks2016.HumanResources.Employee
-- ============================================================
DECLARE @batch_id    VARCHAR(36)  = CONVERT(VARCHAR(36), NEWID());
DECLARE @ingested_at DATETIME2(0) = SYSUTCDATETIME();

PRINT 'Loading raw_hr.employees...';

MERGE [raw_hr].[employees] AS target
USING (
    SELECT
        BusinessEntityID            AS business_entity_id,
        NationalIDNumber            AS national_id_number,
        LoginID                     AS login_id,
        JobTitle                    AS job_title,
        BirthDate                   AS birth_date,
        MaritalStatus               AS marital_status,
        Gender                      AS gender,
        HireDate                    AS hire_date,
        SalariedFlag                AS salaried_flag,
        VacationHours               AS vacation_hours,
        SickLeaveHours              AS sick_leave_hours,
        CONVERT(VARCHAR(64),
            HASHBYTES('SHA2_256',
                CONCAT(
                    CAST(BusinessEntityID AS VARCHAR),   '|',
                    ISNULL(NationalIDNumber, ''),         '|',
                    ISNULL(JobTitle, ''),                 '|',
                    ISNULL(CAST(HireDate AS VARCHAR), '')
                )
            ), 2
        )                           AS _raw_hash
    FROM AdventureWorks2016.HumanResources.Employee
) AS source ON target.[business_entity_id] = source.[business_entity_id]
WHEN MATCHED AND target.[_raw_hash] <> source.[_raw_hash] THEN
    UPDATE SET
        target.[job_title]         = source.[job_title],
        target.[vacation_hours]    = source.[vacation_hours],
        target.[sick_leave_hours]  = source.[sick_leave_hours],
        target.[_ingested_at]      = @ingested_at,
        target.[_batch_id]         = @batch_id,
        target.[_raw_hash]         = source.[_raw_hash],
        target.[_is_deleted]       = 0
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        [business_entity_id], [national_id_number], [login_id], [job_title],
        [birth_date], [marital_status], [gender], [hire_date],
        [salaried_flag], [vacation_hours], [sick_leave_hours],
        [_ingested_at], [_source_system], [_source_entity],
        [_pipeline_name], [_batch_id], [_raw_hash], [_is_deleted]
    )
    VALUES (
        source.[business_entity_id], source.[national_id_number], source.[login_id], source.[job_title],
        source.[birth_date], source.[marital_status], source.[gender], source.[hire_date],
        source.[salaried_flag], source.[vacation_hours], source.[sick_leave_hours],
        @ingested_at, 'hr', 'employees',
        'pl_load_hr_employees_full', @batch_id, source.[_raw_hash], 0
    );

PRINT '  -> raw_hr.employees: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows affected';
GO

-- ============================================================
-- raw_hr.departments
-- Fuente: AdventureWorks2016.HumanResources.Department
-- ============================================================
DECLARE @batch_id    VARCHAR(36)  = CONVERT(VARCHAR(36), NEWID());
DECLARE @ingested_at DATETIME2(0) = SYSUTCDATETIME();

PRINT 'Loading raw_hr.departments...';

MERGE [raw_hr].[departments] AS target
USING (
    SELECT
        DepartmentID                AS department_id,
        Name                        AS name,
        GroupName                   AS group_name,
        CONVERT(VARCHAR(64),
            HASHBYTES('SHA2_256',
                CONCAT(
                    CAST(DepartmentID AS VARCHAR), '|',
                    ISNULL(Name, ''),              '|',
                    ISNULL(GroupName, '')
                )
            ), 2
        )                           AS _raw_hash
    FROM AdventureWorks2016.HumanResources.Department
) AS source ON target.[department_id] = source.[department_id]
WHEN MATCHED AND target.[_raw_hash] <> source.[_raw_hash] THEN
    UPDATE SET
        target.[name]           = source.[name],
        target.[group_name]     = source.[group_name],
        target.[_ingested_at]   = @ingested_at,
        target.[_batch_id]      = @batch_id,
        target.[_raw_hash]      = source.[_raw_hash],
        target.[_is_deleted]    = 0
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        [department_id], [name], [group_name],
        [_ingested_at], [_source_system], [_source_entity],
        [_pipeline_name], [_batch_id], [_raw_hash], [_is_deleted]
    )
    VALUES (
        source.[department_id], source.[name], source.[group_name],
        @ingested_at, 'hr', 'departments',
        'pl_load_hr_departments_full', @batch_id, source.[_raw_hash], 0
    );

PRINT '  -> raw_hr.departments: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows affected';
GO

-- ============================================================
-- VERIFICACIÓN FINAL
-- ============================================================
PRINT '-----------------------------------------------------';
PRINT 'Load summary:';

SELECT
    s.name + '.' + t.name          AS [table],
    p.rows                          AS [row_count]
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1)
WHERE s.name IN ('raw_crm', 'raw_erp', 'raw_hr')
ORDER BY s.name, t.name;
GO
