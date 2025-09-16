-- SQL Server Script: Find Tables with Specific Columns and Apply Dynamic Data Masking
-- Author: Claude
-- Purpose: Locate tables containing specified columns and apply Dynamic Data Masking with permissions

-- =====================================================
-- CONFIGURATION SECTION
-- =====================================================
-- Set to 1 to preview changes, 0 to execute updates
DECLARE @PreviewMode BIT = 1
-- Set to 1 to apply to whole database, 0 to use specific tables only
DECLARE @WholeDB BIT = 0
-- Define specific tables to apply masking to (leave empty for whole DB)
DECLARE @TablesToApply TABLE (TableName NVARCHAR(128))
INSERT INTO @TablesToApply VALUES 
     ('ClientsMasktest'), ('Intermediaries'),('beneficiaries'),('bankdetails'),('OnlineQuotations'),('OnlineQuoteBeneficiaries'),('Clients');
   --('beneficiaries');
   
-- Add more table names as needed

-- Define the column names you want to search for (case-insensitive)
DECLARE @ColumnsToFind TABLE (ColumnName NVARCHAR(128))
--INSERT INTO @ColumnsToFind VALUES 
--       ('Surname'),('OtherNames'),('DateOfBirth'),('PINNo'),('IDNo'),('MobileNo1'),('MobileNo2'),('Email'),--clients
--  ('FullName'), ('PostalAddress'), ('PhysicalAddress'), ('MobileNo1'), ('MobileNo2'), ('Email'), ('PINNo'), ('DateOfBirth'), --Intermediaries
--  ('BeneficiaryName'), ('DateOfBirth'), ('PostalCode'), ('MobileNo'), ('Email'), ('PINNo'), ('IDNo'), --Beneficiaries
--  ('AccountNo'), ('AccountName'), -- bankdetails
--  ('Surname'), ('Othernames'), ('dOB'), ('MobileNo'), ('Email'), ('IdNumber'), ('PinNumber'),--- OnlineQuotations
--  ('BeneficiaryName'), ('DateOfBirth'), ('PostalAddress'), ('MobileNo'), ('Email'), ('PINNo'), ('IDNo') -- OnlineQuoteBeneficiaries

  INSERT INTO @ColumnsToFind VALUES 
   ('AccountName'), ('AccountNo'), ('BeneficiaryName'), ('DateOfBirth'), ('dOB'), ('Email'), ('FullName'), ('IDNo'), ('IdNumber'), 
   ('MobileNo'), ('MobileNo1'), ('MobileNo2'), ('OtherNames'), ('Othernames'), ('PhysicalAddress'), ('PINNo'),
   ('PinNumber'), ('PostalAddress'), ('PostalCode'), ('Surname'),('TelNo'),('Phone')
-- Add more column names as needed
-- Add more column names as needed

-- Define masking functions for Dynamic Data Masking
DECLARE @DefaultMaskFunction NVARCHAR(100) = 'default()'
DECLARE @EmailMaskFunction NVARCHAR(100) = 'email()'
DECLARE @PhoneMaskFunction NVARCHAR(100) = 'partial(0,"XXX-XXX-",4)'
DECLARE @PartialMaskFunction NVARCHAR(100) = 'partial(1,"XXX",2)'

-- Users/Roles that should have UNMASK permission (comma-separated)
DECLARE @UnmaskUsers NVARCHAR(MAX) = 'dbo,db_owner,AdminRole'



-- =====================================================
-- FIND TABLES AND COLUMNS
-- =====================================================

DECLARE @TablesAndColumns TABLE (
    SchemaName NVARCHAR(128),
    TableName NVARCHAR(128),
    ColumnName NVARCHAR(128),
    DataType NVARCHAR(128),
    ColMaxLength INT,
    IsNullable BIT
)

-- Find all tables containing the specified columns
INSERT INTO @TablesAndColumns
SELECT 
    s.name AS SchemaName,
    t.name AS TableName,
    c.name AS ColumnName,
    typ.name AS DataType,
    c.max_length,
    c.is_nullable
FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.columns c ON t.object_id = c.object_id
    INNER JOIN sys.types typ ON c.user_type_id = typ.user_type_id
    INNER JOIN @ColumnsToFind ctf ON LOWER(c.name) like  '%'+LOWER(ctf.ColumnName)+'%'
WHERE (t.name IN (SELECT TableName FROM @TablesToApply) OR @WholeDB = 1)
    AND c.is_masked = 0  
	--and c.name in (select ColumnName from @ColumnsToFind)
ORDER BY s.name, t.name, c.name

select * from @TablesAndColumns

-- Display found tables and columns
PRINT '====================================================='
PRINT 'TABLES AND COLUMNS FOUND:'
PRINT '====================================================='

DECLARE @CurrentSchema NVARCHAR(128) = ''
DECLARE @CurrentTable NVARCHAR(128) = ''
DECLARE @Message NVARCHAR(500)

DECLARE column_cursor CURSOR FOR
SELECT SchemaName, TableName, ColumnName, DataType, ColMaxLength, IsNullable
FROM @TablesAndColumns
ORDER BY SchemaName, TableName, ColumnName

OPEN column_cursor
DECLARE @Schema NVARCHAR(128), @Table NVARCHAR(128), @Column NVARCHAR(128)
DECLARE @DataType NVARCHAR(128), @MaxLength INT, @IsNullable BIT

FETCH NEXT FROM column_cursor INTO @Schema, @Table, @Column, @DataType, @MaxLength, @IsNullable

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @Schema != @CurrentSchema OR @Table != @CurrentTable
    BEGIN
        SET @Message = 'Table: [' + @Schema + '].[' + @Table + ']'
        PRINT @Message
        SET @CurrentSchema = @Schema
        SET @CurrentTable = @Table
    END
    --select @MaxLength
    SET @Message = '  - Column: ' + @Column + ' (' + @DataType + 
                   CASE 
                       WHEN @DataType IN ('varchar', 'nvarchar', 'char', 'nchar') 
                       THEN '(' + CASE WHEN @MaxLength = -1 THEN 'MAX' ELSE CAST(@MaxLength AS VARCHAR(10)) END + ')'
                       ELSE ''
                   END + 
                   CASE WHEN @IsNullable = 1 THEN ' NULL' ELSE ' NOT NULL' END + ')'
    PRINT @Message
    
    FETCH NEXT FROM column_cursor INTO @Schema, @Table, @Column, @DataType, @MaxLength, @IsNullable
END

CLOSE column_cursor
DEALLOCATE column_cursor

-- =====================================================
-- GENERATE AND EXECUTE MASKING STATEMENTS
-- =====================================================

PRINT ''
PRINT '====================================================='
PRINT 'MASKING OPERATIONS:'
PRINT '====================================================='

IF @PreviewMode = 1
BEGIN
    PRINT 'PREVIEW MODE - No data will be modified'
    PRINT ''
END

DECLARE masking_cursor CURSOR FOR
SELECT SchemaName, TableName, ColumnName, DataType,ColMaxLength, IsNullable
FROM @TablesAndColumns
ORDER BY SchemaName, TableName, ColumnName

OPEN masking_cursor
FETCH NEXT FROM masking_cursor INTO @Schema, @Table, @Column, @DataType, @MaxLength, @IsNullable

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @SQL NVARCHAR(4000)
    DECLARE @MaskValue NVARCHAR(50)
    
    -- Determine appropriate mask based on column name
    SET @MaskValue = CASE 
        WHEN LOWER(@Column) LIKE '%email%' THEN @EmailMaskFunction
        WHEN LOWER(@Column) LIKE '%phone%' THEN @PhoneMaskFunction
		 WHEN LOWER(@Column) LIKE '%mobile%' THEN @PhoneMaskFunction
    
        ELSE @DefaultMaskFunction
    END
	  DECLARE @DataTypewithLen VARCHAR(100) = @DataType;

	
			Set @DataTypewithLen =  @DataType + 
                   CASE 
                       WHEN @DataType IN ('varchar', 'nvarchar', 'char', 'nchar') 
                       THEN '(' + CASE WHEN @MaxLength = -1 THEN 'MAX' ELSE CAST(@MaxLength AS VARCHAR(10)) END + ')'
                       ELSE ''
                   END 
                   

	
    -- Build UPDATE statement
    SET @SQL = 'ALTER TABLE [' + @Schema + '].[' + @Table + '] ';
	
	SET @SQL = @SQL +  'ALTER COLUMN [' + @Column + '] '  + @DataTypewithLen + ' MASKED WITH (FUNCTION =  ''' + @MaskValue + ''')' ;
    --ALTER COLUMN Surname  VARCHAR(100)  MASKED WITH (FUNCTION ='default()')
    -- Add WHERE clause to avoid updating already masked data
	SET @SQL = @SQL + CASE WHEN @IsNullable = 1 THEN ' NULL' ELSE ' NOT NULL' END
    
    IF @PreviewMode = 1
    BEGIN
        PRINT 'PREVIEW: ' + @SQL
    END
    ELSE
    BEGIN
        PRINT 'EXECUTING: ' + @SQL
        BEGIN TRY
            EXEC sp_executesql @SQL
            PRINT 'SUCCESS: Updated [' + @Schema + '].[' + @Table + '].[' + @Column + ']'
        END TRY
        BEGIN CATCH
            PRINT 'ERROR: Failed to update [' + @Schema + '].[' + @Table + '].[' + @Column + ']'
            PRINT 'Error Message: ' + ERROR_MESSAGE()
        END CATCH
    END
    
    FETCH NEXT FROM masking_cursor INTO @Schema, @Table, @Column, @DataType,@MaxLength, @IsNullable
END

CLOSE masking_cursor
DEALLOCATE masking_cursor

-- =====================================================
-- SUMMARY REPORT
-- =====================================================

PRINT ''
PRINT '====================================================='
PRINT 'SUMMARY REPORT:'
PRINT '====================================================='

DECLARE @TableCount INT, @ColumnCount INT

SELECT @TableCount = COUNT(DISTINCT SchemaName + '.' + TableName),
       @ColumnCount = COUNT(*)
FROM @TablesAndColumns

SET @Message = 'Tables found: ' + CAST(@TableCount AS VARCHAR(10))
PRINT @Message

SET @Message = 'Columns processed: ' + CAST(@ColumnCount AS VARCHAR(10))
PRINT @Message

IF @PreviewMode = 1
BEGIN
    PRINT ''
    PRINT 'To execute the masking operations, set @PreviewMode = 0'
    PRINT 'WARNING: This will apply Dynamic Data Masking to your columns!'
    PRINT 'Make sure to backup your database before running in execution mode.'
    PRINT ''
    PRINT 'IMPORTANT: Dynamic Data Masking does not modify actual data.'
    PRINT 'It only masks the data when queried by users without UNMASK permission.'
END
ELSE
BEGIN
    PRINT ''
    PRINT 'Dynamic Data Masking operations completed.'
    PRINT 'Users without UNMASK permission will see masked data.'
    PRINT 'Users with UNMASK permission will see actual data.'
END

-- =====================================================
-- VERIFICATION AND TESTING QUERIES
-- =====================================================

PRINT ''
PRINT '====================================================='
PRINT 'VERIFICATION QUERIES (Copy and run separately):'
PRINT '====================================================='

-- Show current masking status
PRINT '-- Check current masking configuration:'
PRINT 'SELECT '
PRINT '    SCHEMA_NAME(t.schema_id) AS SchemaName,'
PRINT '    t.name AS TableName,'
PRINT '    c.name AS ColumnName,'
PRINT '    c.is_masked,'
PRINT '    c.masking_function'
PRINT 'FROM sys.tables t'
PRINT '    INNER JOIN sys.columns c ON t.object_id = c.object_id'
PRINT 'WHERE c.is_masked = 1'
PRINT 'ORDER BY SCHEMA_NAME(t.schema_id), t.name, c.name'
PRINT ''

-- Show users with UNMASK permission
PRINT '-- Check users/roles with UNMASK permission:'
PRINT 'SELECT '
PRINT '    p.state_desc AS permission_state,'
PRINT '    p.permission_name,'
PRINT '    pr.name AS principal_name,'
PRINT '    pr.type_desc AS principal_type'
PRINT 'FROM sys.database_permissions p'
PRINT '    INNER JOIN sys.database_principals pr ON p.grantee_principal_id = pr.principal_id'
PRINT 'WHERE p.permission_name = ''UNMASK'''
PRINT ''

DECLARE verify_cursor CURSOR FOR
SELECT DISTINCT SchemaName, TableName
FROM @TablesAndColumns
ORDER BY SchemaName, TableName

OPEN verify_cursor
FETCH NEXT FROM verify_cursor INTO @Schema, @Table

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = '-- Test masking on table [' + @Schema + '].[' + @Table + ']'
    PRINT @SQL
    SET @SQL = 'SELECT TOP 10 * FROM [' + @Schema + '].[' + @Table + ']'
    PRINT @SQL
    PRINT ''
    FETCH NEXT FROM verify_cursor INTO @Schema, @Table
END

CLOSE verify_cursor
DEALLOCATE verify_cursor

PRINT '-- To test masking effectiveness:'
PRINT '-- 1. Create a test user: CREATE USER TestUser WITHOUT LOGIN'
PRINT '-- 2. Grant SELECT permission: GRANT SELECT ON SCHEMA::dbo TO TestUser'  
PRINT '-- 3. Execute as test user: EXECUTE AS USER = ''TestUser'''
PRINT '-- 4. Query masked tables to see masked data'
PRINT '-- 5. Revert to original user: REVERT'