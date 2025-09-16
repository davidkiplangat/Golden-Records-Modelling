---------------------------------------------------------
-- 0. Helper Functions
---------------------------------------------------------

-- (a) RemoveNonDigits
IF OBJECT_ID('dbo.RemoveNonDigits','FN') IS NOT NULL
    DROP FUNCTION dbo.RemoveNonDigits;
GO
CREATE FUNCTION dbo.RemoveNonDigits(@s NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @i INT = 1, @len INT = LEN(ISNULL(@s,'')), @out NVARCHAR(MAX) = '';
    WHILE @i <= @len
    BEGIN
        DECLARE @ch NCHAR(1) = SUBSTRING(@s, @i, 1);
        IF UNICODE(@ch) BETWEEN 48 AND 57
            SET @out += @ch;
        SET @i += 1;
    END
    RETURN @out;
END
GO

-- (b) NormalizeAndSortName
IF OBJECT_ID('dbo.NormalizeAndSortName','FN') IS NOT NULL
    DROP FUNCTION dbo.NormalizeAndSortName;
GO
CREATE FUNCTION dbo.NormalizeAndSortName(@name VARCHAR(MAX))
RETURNS VARCHAR(MAX)
AS
BEGIN
    DECLARE @output VARCHAR(MAX) = '';
    DECLARE @xml XML;

    SET @xml = N'<t>' + REPLACE(LOWER(LTRIM(RTRIM(ISNULL(@name,'')))), ' ', '</t><t>') + '</t>';

    SELECT @output = @output + T.c.value('.', 'VARCHAR(MAX)') + '_'
    FROM @xml.nodes('/t') AS T(c)
    ORDER BY T.c.value('.', 'VARCHAR(MAX)');

    IF LEN(@output) > 0
        SET @output = LEFT(@output, LEN(@output) - 1);

    RETURN @output;
END
GO

-- (c) NormalizeFullSurrogate
IF OBJECT_ID('dbo.NormalizeFullSurrogate','FN') IS NOT NULL
    DROP FUNCTION dbo.NormalizeFullSurrogate;
GO
CREATE FUNCTION dbo.NormalizeFullSurrogate
(
    @name NVARCHAR(MAX),
    @email NVARCHAR(MAX),
    @phone NVARCHAR(MAX),
    @nationalid NVARCHAR(MAX),
    @tin NVARCHAR(MAX),
    @location NVARCHAR(MAX),
    @customertype NVARCHAR(MAX)
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE 
        @nname NVARCHAR(MAX) = dbo.NormalizeAndSortName(ISNULL(@name,'')),
        @nemail NVARCHAR(MAX) = LOWER(LTRIM(RTRIM(ISNULL(@email,'')))),
        @nphone NVARCHAR(MAX) = dbo.RemoveNonDigits(ISNULL(@phone,'')),
        @nid NVARCHAR(MAX)    = LTRIM(RTRIM(ISNULL(@nationalid,''))),
        @ntin NVARCHAR(MAX)   = LTRIM(RTRIM(ISNULL(@tin,''))),
        @nloc NVARCHAR(MAX)   = LOWER(LTRIM(RTRIM(ISNULL(@location,'')))),
        @ntype NVARCHAR(MAX)  = LOWER(LTRIM(RTRIM(ISNULL(@customertype,''))));

    RETURN CONCAT_WS(
        '_',
        NULLIF(@nname,''), 
        NULLIF(@nemail,''), 
        NULLIF(@nphone,''), 
        NULLIF(@nid,''), 
        NULLIF(@ntin,''), 
        NULLIF(@nloc,''), 
        NULLIF(@ntype,'')
    );
END
GO

---------------------------------------------------------
-- 1. CustomerStage (raw input staging)
-----------------------------------------------------------
--IF OBJECT_ID('dbo.CustomerStage') IS NOT NULL
--    DROP TABLE dbo.CustomerStage;
--GO

--CREATE TABLE dbo.CustomerStage
--(
--    ClientNo INT PRIMARY KEY,
--    CustomerKey INT NULL,
--    Name NVARCHAR(255) NULL,
--    CustomerType NVARCHAR(100) NULL,
--    Phone NVARCHAR(50) NULL,
--    Email NVARCHAR(255) NULL,
--    NationalID NVARCHAR(50) NULL,
--    TIN NVARCHAR(50) NULL,
--    Location NVARCHAR(100) NULL,
--    -- computed later:
--    FullSurrogate NVARCHAR(MAX) NULL,
--    NormalizedSurrogate NVARCHAR(MAX) NULL,
--    CustomerUnifiedID INT NULL
--);

---------------------------------------------------------
---- 2. Insert Sample Data (edge cases included)
-----------------------------------------------------------
--INSERT INTO dbo.CustomerStage (ClientNo, CustomerKey, Name, CustomerType, Phone, Email, NationalID, TIN, Location)
--VALUES
--(101,1,'John Smith','Retail','0712345678','john.smith@email.com','12345678','TIN001','Nairobi'),
--(102,2,'Jon Smith','Retail','712345678','jon.s@email.com','12345678','TIN001','Nairobi'),
--(106,3,'John Smith','Retail','0712345678','john.smith2@email.com','12345678',NULL,'Nairobi'),
--(107,4,'J. Smith','Retail','0712345679','jsmith@email.com',NULL,NULL,'Nairobi'),
--(112,5,'John Smyth','Retail','0712345600','john.smyth@email.com','12345678','TIN001','Nairobi'),
--(103,6,'Mary Achieng','Corporate','0734567890','mary.a@email.com','87654321','TIN002','Kisumu'),
--(104,7,'Mary Acheng','Corporate','734567890','maryachieng@email.com','87654321','TIN002','Kisumu'),
--(108,8,'Mary Achieng','Corporate','0734567899','mary.alt@email.com',NULL,'TIN002','Kisumu'),
--(109,9,'M. Achieng','Corporate','0734567800','m.achieng@email.com',NULL,NULL,'Kisumu'),
--(113,10,'Marie Achieng','Corporate','0734567891','marie.a@email.com','87654321','TIN002','Kisumu'),
--(105,11,'Peter Kariuki','Retail','0722001122','peter.k@email.com','11223344','TIN003','Mombasa'),
--(110,12,'Peter Kariuki','Retail','0722001123','peter.alt@email.com','11223344',NULL,'Mombasa'),
--(111,13,'P. Kariuki','Retail','0722001125','pk@email.com',NULL,NULL,'Mombasa'),
--(114,14,'Peter Kariok','Retail','0722001130','peter.kariok@email.com','11223344','TIN003','Mombasa'),
--(201,15,'Alice Mwangi','Corporate','0744001234','alice@email.com','55667788','TIN004','Nakuru'),
--(202,16,'Alyce Mwangi','Corporate','744001234','alyce@email.com','55667788','TIN004','Nakuru'),
--(203,17,'Alice Mwangi','Corporate','0744001235','alice2@email.com',NULL,'TIN004','Nakuru'),
--(204,18,'A. Mwangi','Corporate','0744001200','a.mwangi@email.com',NULL,NULL,'Nakuru'),
--(301,19,'David Otieno','Retail','0755002233','david@email.com','99887766','TIN005','Eldoret'),
--(302,20,'Dave Otieno','Retail','755002233','dave@email.com','99887766','TIN005','Eldoret'),
--(303,21,'David Otieno','Retail','0755002234','david2@email.com',NULL,'TIN005','Eldoret'),
--(304,22,'D. Otieno','Retail','0755002200','d.otieno@email.com',NULL,NULL,'Eldoret'),
--(10001,23,'John Karanja','Individual','0722123456','johnk@example.com',NULL,NULL,'Nairobi'),
--(10002,24,'J. Karanja','Individual','0722123456','john.k@example.com',NULL,NULL,'Nairobi'),
--(10003,25,'Mary Wanjiku','Individual','0722987654','maryw@example.com',NULL,NULL,'Mombasa'),
--(10004,26,'M. Wanjiku','Individual','0722987654','mwanjiku@example.com',NULL,NULL,'Mombasa'),
--(10005,27,'Peter Otieno','Business','0733123123','peter.otieno@example.com',NULL,NULL,'Kisumu'),
--(10006,28,'P. Otieno','Business','0733123123','potieno@example.com',NULL,NULL,'Kisumu');

---------------------------------------------------------
-- 3. Update Surrogate Columns
---------------------------------------------------------

-- FullSurrogate (raw concatenation, human-readable)
UPDATE dbo.CustomerStage
SET FullSurrogate = CONCAT_WS(
        '_',
        ISNULL(Name,''),
        ISNULL(CustomerType,''),
        dbo.RemoveNonDigits(ISNULL(Phone,'')),
        LOWER(LTRIM(RTRIM(ISNULL(Email,'')))),
        ISNULL(NationalID,''),
        ISNULL(TIN,''),
        LOWER(LTRIM(RTRIM(ISNULL(Location,''))))
    );

-- NormalizedSurrogate (clean + token sorted + stable)
UPDATE dbo.CustomerStage
SET NormalizedSurrogate = dbo.NormalizeFullSurrogate(
        Name, Email, Phone, NationalID, TIN, Location, CustomerType
    );

-- Assign temporary CustomerUnifiedID (later replaced by clustering)
;WITH cte AS (
    SELECT ClientNo, ROW_NUMBER() OVER (ORDER BY ClientNo) AS rn
    FROM dbo.CustomerStage
)
UPDATE s
SET s.CustomerUnifiedID = c.rn
FROM dbo.CustomerStage s
JOIN cte c ON s.ClientNo = c.ClientNo;

---------------------------------------------------------
-- 4. CandidatePairs (blocking on stable signals)
---------------------------------------------------------
IF OBJECT_ID('dbo.CandidatePairs') IS NOT NULL DROP TABLE dbo.CandidatePairs;
GO

SELECT DISTINCT
    a.ClientNo AS ClientA,
    b.ClientNo AS ClientB,
    a.FullSurrogate AS FullA,
    b.FullSurrogate AS FullB,
    a.NormalizedSurrogate AS NormSurrogateA,
    b.NormalizedSurrogate AS NormSurrogateB,
    a.CustomerUnifiedID AS UnifiedA,
    b.CustomerUnifiedID AS UnifiedB,
    a.NationalID AS NationalIDA,
    b.NationalID AS NationalIDB,
    a.TIN AS TINA,
    b.TIN AS TINB,
    LOWER(ISNULL(a.Email,'')) AS EmailA,
    LOWER(ISNULL(b.Email,'')) AS EmailB,
    dbo.RemoveNonDigits(ISNULL(a.Phone,'')) AS PhoneA,
    dbo.RemoveNonDigits(ISNULL(b.Phone,'')) AS PhoneB
INTO dbo.CandidatePairs
FROM dbo.CustomerStage a
JOIN dbo.CustomerStage b
    ON a.ClientNo < b.ClientNo
   AND (
         (ISNULL(a.NationalID,'') <> '' AND a.NationalID = b.NationalID)
      OR (ISNULL(a.TIN,'') <> '' AND a.TIN = b.TIN)
      OR (LOWER(ISNULL(a.Email,'')) <> '' AND LOWER(ISNULL(a.Email,'')) = LOWER(ISNULL(b.Email,'')))
      OR (dbo.RemoveNonDigits(ISNULL(a.Phone,'')) <> '' AND dbo.RemoveNonDigits(ISNULL(a.Phone,'')) = dbo.RemoveNonDigits(ISNULL(b.Phone,'')))
      OR (LEFT(a.NormalizedSurrogate, 20) = LEFT(b.NormalizedSurrogate, 20))
   );



SELECT TOP 2 * FROM CUSTOMERS;
SELECT TOP 2 * FROM CUSTOMERStage;
Select * from dbo.CandidatePairs

-----------------------------------------


------------------------------------------

---------------------------------------------------------
-- 3. Fuzzy Match Results
---------------------------------------------------------
IF OBJECT_ID('dbo.FuzzyResults') IS NOT NULL DROP TABLE dbo.FuzzyResults;
GO

SELECT 
    cp.CustomerA,
    cp.CustomerB,
    cp.UnifiedA,
    cp.UnifiedB,
    cp.FullA,
    cp.FullB,
    cp.NormSurrogateA,
    cp.NormSurrogateB,
    cp.NationalIDA,
    cp.NationalIDB,
    cp.TINA,
    cp.TINB,
    cp.EmailA,
    cp.EmailB,
    cp.PhoneA,
    cp.PhoneB,

-- Compute similarity %
MatchPercent = CAST(
    CASE 
        WHEN (1.0 - 
              (CAST(dbo.Levenshtein(cp.NormSurrogateA, cp.NormSurrogateB) AS FLOAT) /
               NULLIF(CASE 
                          WHEN LEN(cp.NormSurrogateA) > LEN(cp.NormSurrogateB) 
                          THEN LEN(cp.NormSurrogateA) 
                          ELSE LEN(cp.NormSurrogateB) 
                      END, 0)
              )
             ) * 100 < 0
        THEN 0
        ELSE (1.0 - 
              (CAST(dbo.Levenshtein(cp.NormSurrogateA, cp.NormSurrogateB) AS FLOAT) /
               NULLIF(CASE 
                          WHEN LEN(cp.NormSurrogateA) > LEN(cp.NormSurrogateB) 
                          THEN LEN(cp.NormSurrogateA) 
                          ELSE LEN(cp.NormSurrogateB) 
                      END, 0)
              )
             ) * 100
    END
AS DECIMAL(5,2)
),


    -- Bonus flags for stronger signals
    ExactNationalID = CASE WHEN cp.NationalIDA IS NOT NULL AND cp.NationalIDA = cp.NationalIDB THEN 1 ELSE 0 END,
    ExactTIN        = CASE WHEN cp.TINA IS NOT NULL AND cp.TINA = cp.TINB THEN 1 ELSE 0 END,
    ExactEmail      = CASE WHEN cp.EmailA <> '' AND cp.EmailA = cp.EmailB THEN 1 ELSE 0 END,
    ExactPhone      = CASE WHEN cp.PhoneA <> '' AND cp.PhoneA = cp.PhoneB THEN 1 ELSE 0 END
INTO dbo.FuzzyResults
FROM dbo.CandidatePairs cp
WHERE cp.CustomerA < cp.CustomerB;

-----------------------------------------


------------------------------------------

SELECT TOP 2 * FROM CUSTOMERS;
SELECT TOP 2 * FROM CUSTOMERStage;
Select Top 2 * from dbo.CandidatePairs;
SELECT * FROM dbo.FuzzyResults ORDER BY 3,4, MatchPercent Desc;
SELECT * FROM dbo.CustomerClusters ORDER BY CustomerUnifiedID;


-----------------------------------------


------------------------------------------



---------------------------------------------------------
-- 5. Clustering: Assign a unified ID to linked customers
---------------------------------------------------------

IF OBJECT_ID('dbo.CustomerClusters') IS NOT NULL 
    DROP TABLE dbo.CustomerClusters;
GO

;WITH InitialLinks AS
(
    -- Keep only strong enough links
    SELECT 
        fr.CustomerA,
        fr.CustomerB
    FROM dbo.FuzzyResults fr
    WHERE fr.MatchPercent >= 70  -- configurable threshold
),
RecursiveClusters AS
(
    -- Anchor: start with each customer
    SELECT 
        CustomerA AS CustomerID,
        CustomerA AS RootID
    FROM InitialLinks
    UNION ALL
    -- Recurse: bring in all connected neighbors
    SELECT 
        il.CustomerB AS CustomerID,
        rc.RootID
    FROM RecursiveClusters rc
    JOIN InitialLinks il
        ON rc.CustomerID = il.CustomerA
),
Clusteredd AS
(
    -- Reduce to one root per customer (smallest RootID ensures determinism)
    SELECT 
        CustomerID,
        MIN(RootID) AS CustomerUnifiedID
    FROM RecursiveClusters
    GROUP BY CustomerID
)
-- Materialize
SELECT 
    ROW_NUMBER() OVER (ORDER BY CustomerUnifiedID, CustomerID) AS ClusterRow,
    CustomerID,
    CustomerUnifiedID
--INTO dbo.CustomerClusters
FROM Clusteredd;

-- Quick check
SELECT TOP 2 * FROM CUSTOMERS;
SELECT TOP 2 * FROM CUSTOMERStage;
Select Top 2 * from dbo.CandidatePairs;
SELECT * FROM dbo.FuzzyResults ORDER BY 3,4, MatchPercent Desc;
SELECT * FROM dbo.CustomerClusters ORDER BY CustomerUnifiedID;




---------------------------------------------------------
-- Build CustomerMaster with aggregated SourceClientNos
---------------------------------------------------------
IF OBJECT_ID('dbo.CustomerMaster') IS NOT NULL DROP TABLE dbo.CustomerMaster;
GO

;WITH Grouped AS
(
    SELECT 
        cc.CustomerUnifiedID,
        STRING_AGG(CAST(cc.CustomerID AS VARCHAR(20)), ',') AS SourceClientNos,
        MAX(cs.NormalizedSurrogate) AS NormalizedSurrogate,
        MAX(cs.Name) AS Name,
        MAX(cs.CustomerType) AS CustomerType,
        MAX(cs.Phone) AS Phone,
        MAX(cs.Email) AS Email,
        MAX(cs.NationalID) AS NationalID,
        MAX(cs.TIN) AS TIN,
        MAX(cs.Location) AS Location
    FROM dbo.CustomerClusters cc
    JOIN dbo.CustomerStage cs
      ON cc.CustomerID = cs.ClientNo   -- 🔑 match staging records
    GROUP BY cc.CustomerUnifiedID
)
SELECT 
    ROW_NUMBER() OVER (ORDER BY g.CustomerUnifiedID) AS MasterCustomerID,
    g.CustomerUnifiedID,
    g.SourceClientNos,
    g.NormalizedSurrogate,
    g.Name,
    g.CustomerType,
    g.Phone,
    g.Email,
    g.NationalID,
    g.TIN,
    g.Location
INTO dbo.CustomerMaster
FROM Grouped g;

 --Check result
SELECT * FROM dbo.CustomerMaster ORDER BY CustomerUnifiedID;


SELECT TOP 2 * FROM CUSTOMERS;
SELECT TOP 2 * FROM CUSTOMERStage;
Select Top 2 * from dbo.CandidatePairs;
SELECT * FROM dbo.FuzzyResults ORDER BY 3,4, MatchPercent Desc;
SELECT * FROM dbo.CustomerClusters ORDER BY CustomerUnifiedID;
SELECT TOP 2 * FROM dbo.CustomerMaster ORDER BY CustomerUnifiedID;

SELECT DISTINCT 
		CustomerA,CustomerB,
		FullA,FullB,NormSurrogateA,NormSurrogateB,NationalIDA ,
		NationalIDB,TINA,TINB,EmailA,EmailB,PhoneA,PhoneB,
		MatchPercent,ExactNationalID,ExactNationalID,ExactTIN,ExactPhone
	FROM dbo.FuzzyResults 
Where CustomerA in (
			SELECT DISTINCT CustomerID FROM dbo.CustomerClusters 
			WHERE CustomerUnifiedID = 101
			)
	ORDER BY MatchPercent DESC,CustomerA,CustomerB Desc