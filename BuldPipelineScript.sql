--CREATE SCHEMA Bronze

--SELECT * 
----INTO Bronze.Customers
--FROM Bronze.Customers
--1. Stage Load
IF OBJECT_ID('dbo.sp_LoadCustomerStage','P') IS NOT NULL DROP PROCEDURE dbo.sp_LoadCustomerStage;
GO
CREATE PROCEDURE dbo.sp_LoadCustomerStage
AS
BEGIN
    SET NOCOUNT ON;
    IF OBJECT_ID('Bronze.CustomerStage') IS NOT NULL DROP TABLE Bronze.CustomerStage;
	SELECT * 
	INTO Bronze.CustomerStage
	FROM Bronze.Customers 
	ORDER BY ClientNo,Name
END
GO
--EXEC dbo.sp_LoadCustomerStage
SELECT TOP 20 * FROM Bronze.CustomerStage 

----2. Surrogate Build

IF OBJECT_ID('dbo.sp_BuildSurrogates','P') IS NOT NULL 
    DROP PROCEDURE dbo.sp_BuildSurrogates;
GO
CREATE PROCEDURE dbo.sp_BuildSurrogates
AS
BEGIN
    SET NOCOUNT ON;
    -- Ensure required columns exist
    IF COL_LENGTH('Bronze.CustomerStage','FullSurrogate') IS NULL
        ALTER TABLE Bronze.CustomerStage ADD FullSurrogate NVARCHAR(500);
    IF COL_LENGTH('Bronze.CustomerStage','NormalizedSurrogate') IS NULL
        ALTER TABLE Bronze.CustomerStage ADD NormalizedSurrogate NVARCHAR(500);
    IF COL_LENGTH('Bronze.CustomerStage','CustomerUnifiedID') IS NULL
        ALTER TABLE Bronze.CustomerStage ADD CustomerUnifiedID BIGINT;
    -------------------------------------------------------------------
    -- Build full surrogate
    -------------------------------------------------------------------
    UPDATE Bronze.CustomerStage
    SET FullSurrogate = CONCAT_WS('_',
        ISNULL(Name,''), ISNULL(CustomerType,''), dbo.RemoveNonDigits(ISNULL(Phone,'')),
        LOWER(LTRIM(RTRIM(ISNULL(Email,'')))), ISNULL(NationalID,''), ISNULL(TIN,''), LOWER(ISNULL(Location,'')));
    -------------------------------------------------------------------
    -- Build normalized surrogate (requires dbo.NormalizeFullSurrogate)
    -------------------------------------------------------------------
    UPDATE Bronze.CustomerStage
    SET NormalizedSurrogate = dbo.NormalizeFullSurrogate(Name, Email, Phone, NationalID, TIN, Location, CustomerType);
    -------------------------------------------------------------------
    -- Assign a deterministic surrogate key using HASH
    -- (stable across reloads, unlike ROW_NUMBER)
    -------------------------------------------------------------------
    UPDATE Bronze.CustomerStage
    SET CustomerUnifiedID = ABS(CHECKSUM(NormalizedSurrogate));
END
GO

SELECT TOP 2 * FROM Bronze.CustomerStage
EXEC dbo.sp_BuildSurrogates
SELECT TOP 2 * FROM Bronze.CustomerStage


-- 3. Candidate Pairs
---------------------------------------------------------
IF OBJECT_ID('dbo.sp_BuildCandidatePairs','P') IS NOT NULL DROP PROCEDURE dbo.sp_BuildCandidatePairs;
GO
CREATE PROCEDURE dbo.sp_BuildCandidatePairs
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('Bronze.CandidatePairs') IS NOT NULL DROP TABLE Bronze.CandidatePairs;

    SELECT DISTINCT
        a.ClientNo AS ClientNoA,
        b.ClientNo AS ClientNoB,
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
    INTO Bronze.CandidatePairs
    FROM Bronze.CustomerStage a
    JOIN Bronze.CustomerStage b
        ON a.ClientNo < b.ClientNo
       AND (
             (ISNULL(a.NationalID,'') <> '' AND a.NationalID = b.NationalID)
          OR (ISNULL(a.TIN,'') <> '' AND a.TIN = b.TIN)
          OR (LOWER(ISNULL(a.Email,'')) <> '' AND LOWER(ISNULL(a.Email,'')) = LOWER(ISNULL(b.Email,'')))
          OR (dbo.RemoveNonDigits(ISNULL(a.Phone,'')) <> '' AND dbo.RemoveNonDigits(ISNULL(a.Phone,'')) = dbo.RemoveNonDigits(ISNULL(b.Phone,'')))
          OR (LEFT(a.NormalizedSurrogate, 20) = LEFT(b.NormalizedSurrogate, 20))
       );
END
GO

--SELECT TOP 2 * FROM  Bronze.CandidatePairs
--EXEC dbo.sp_BuildCandidatePairs;
--SELECT TOP 2 * FROM  Bronze.CandidatePairs


---------------------------------------------------------
-- 4. Fuzzy Results
---------------------------------------------------------
IF OBJECT_ID('dbo.sp_BuildFuzzyResults','P') IS NOT NULL DROP PROCEDURE dbo.sp_BuildFuzzyResults;
GO
CREATE PROCEDURE dbo.sp_BuildFuzzyResults
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('Bronze.FuzzyResults') IS NOT NULL DROP TABLE Bronze.FuzzyResults;

    SELECT 
        cp.ClientNoA,
        cp.ClientNoB,
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
		ExactNationalID = CASE WHEN cp.NationalIDA IS NOT NULL AND cp.NationalIDA = cp.NationalIDB THEN 1 ELSE 0 END,
        ExactTIN        = CASE WHEN cp.TINA IS NOT NULL AND cp.TINA = cp.TINB THEN 1 ELSE 0 END,
        ExactEmail      = CASE WHEN cp.EmailA <> '' AND cp.EmailA = cp.EmailB THEN 1 ELSE 0 END,
        ExactPhone      = CASE WHEN cp.PhoneA <> '' AND cp.PhoneA = cp.PhoneB THEN 1 ELSE 0 END,
        MatchPercent = CAST(
            CASE 
                WHEN (1.0 - (CAST(dbo.Levenshtein(cp.NormSurrogateA, cp.NormSurrogateB) AS FLOAT) / 
                             NULLIF(CASE WHEN LEN(cp.NormSurrogateA) > LEN(cp.NormSurrogateB) 
                                         THEN LEN(cp.NormSurrogateA) ELSE LEN(cp.NormSurrogateB) END, 0)
                            )) * 100 < 0
                THEN 0
                ELSE (1.0 - (CAST(dbo.Levenshtein(cp.NormSurrogateA, cp.NormSurrogateB) AS FLOAT) / 
                             NULLIF(CASE WHEN LEN(cp.NormSurrogateA) > LEN(cp.NormSurrogateB) 
                                         THEN LEN(cp.NormSurrogateA) ELSE LEN(cp.NormSurrogateB) END, 0)
                            )) * 100
            END
        AS DECIMAL(5,2))
    INTO Bronze.FuzzyResults
    FROM Bronze.CandidatePairs cp
    WHERE cp.ClientNoA < cp.ClientNoB
	ORDER BY ClientNoA, MatchPercent DESC;
END
GO
--EXEC dbo.sp_BuildFuzzyResults
--SELECT * FROM Bronze.FuzzyResults 

---------------------------------------------------------
-- 5. Clustering
---------------------------------------------------------
IF OBJECT_ID('dbo.sp_BuildCustomerClusters','P') IS NOT NULL 
    DROP PROCEDURE dbo.sp_BuildCustomerClusters;
GO

CREATE PROCEDURE dbo.sp_BuildCustomerClusters
AS
BEGIN
    SET NOCOUNT ON;

    -- Drop old table if exists
    IF OBJECT_ID('Bronze.CustomerClusters','U') IS NOT NULL 
        DROP TABLE Bronze.CustomerClusters;

    ;WITH InitialLinks AS
    (
        SELECT fr.ClientNoA, fr.ClientNoB, fr.MatchPercent
        FROM Bronze.FuzzyResults fr
        --WHERE fr.MatchPercent >= 70
    ),
    RecursiveClusters AS
    (
        SELECT ClientNoA AS CustomerID, ClientNoA AS RootID
        FROM InitialLinks

        UNION ALL

        SELECT il.ClientNoB, rc.RootID
        FROM RecursiveClusters rc
        JOIN InitialLinks il ON rc.CustomerID = il.ClientNoA
    ),
    Clusteredd AS
    (
        SELECT CustomerID, MIN(RootID) AS RootClientNo
        FROM RecursiveClusters
        GROUP BY CustomerID
    ),
    Deduped AS
    (
        SELECT 
            c.RootClientNo,
            c.CustomerID AS PossibleMatchClientNo,
            MAX(il.MatchPercent) AS MatchPercent
        FROM Clusteredd c
        LEFT JOIN InitialLinks il 
               ON ( (c.CustomerID = il.ClientNoA AND c.RootClientNo = il.ClientNoB)
                 OR (c.CustomerID = il.ClientNoB AND c.RootClientNo = il.ClientNoA) )
        WHERE c.CustomerID <> c.RootClientNo   -- remove self matches
        GROUP BY c.RootClientNo, c.CustomerID
    )
    SELECT 
        ROW_NUMBER() OVER (ORDER BY d.RootClientNo, d.PossibleMatchClientNo) AS ClusterRow,
        d.RootClientNo,
        d.PossibleMatchClientNo,
        d.MatchPercent
    INTO Bronze.CustomerClusters
    FROM Deduped d 
		ORDER BY         
			d.RootClientNo ,
			d.MatchPercent DESC,
			d.PossibleMatchClientNo;
END
GO




SELECT * FROM Bronze.CustomerClusters;
EXEC dbo.sp_BuildCustomerClusters;
SELECT * FROM Bronze.CustomerClusters;

----------------------------------------------------------
-- 6. Customer Master
---------------------------------------------------------
IF OBJECT_ID('dbo.sp_BuildCustomerMaster','P') IS NOT NULL DROP PROCEDURE dbo.sp_BuildCustomerMaster;
GO
CREATE PROCEDURE dbo.sp_BuildCustomerMaster
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID('Silver.CustomerMaster') IS NOT NULL DROP TABLE Silver.CustomerMaster;

    ;WITH Grouped AS
    (
        SELECT 
            cc.RootClientNo,
            STRING_AGG(CAST(cc.PossibleMatchClientNo AS VARCHAR(20)), ',') AS SourceClientNos,
            MAX(cs.Name) AS Name,
            MAX(cs.CustomerType) AS CustomerType,
            MAX(cs.Phone) AS Phone,
            MAX(cs.Email) AS Email,
            MAX(cs.NationalID) AS NationalID,
            MAX(cs.TIN) AS TIN,
            MAX(cs.Location) AS Location,
			MAX(cs.NormalizedSurrogate) AS NormalizedSurrogate
        FROM Bronze.CustomerClusters cc
        JOIN Bronze.CustomerStage cs ON cc.RootClientNo = cs.ClientNo
        GROUP BY cc.RootClientNo
    )
    SELECT ROW_NUMBER() OVER (ORDER BY g.RootClientNo) AS MasterCustomerID,
           g.RootClientNo,
           g.SourceClientNos,
           g.Name,
           g.CustomerType,
           g.Phone,
           g.Email,
           g.NationalID,
           g.TIN,
           g.Location,
		   g.NormalizedSurrogate
    INTO Silver.CustomerMaster
    FROM Grouped g;
END
GO

EXEC dbo.sp_BuildCustomerMaster
SELECT  * FROM Silver.CustomerMaster




---------------------------------------------------------
-- 7. Driver Procedure (run full pipeline)
---------------------------------------------------------
IF OBJECT_ID('dbo.sp_RunCustomerDedupPipeline','P') IS NOT NULL DROP PROCEDURE dbo.sp_RunCustomerDedupPipeline;
GO
CREATE PROCEDURE dbo.sp_RunCustomerDedupPipeline
AS
BEGIN
    EXEC dbo.sp_LoadCustomerStage;
    EXEC dbo.sp_BuildSurrogates;
    EXEC dbo.sp_BuildCandidatePairs;
    EXEC dbo.sp_BuildFuzzyResults;
    EXEC dbo.sp_BuildCustomerClusters;
    EXEC dbo.sp_BuildCustomerMaster;
END