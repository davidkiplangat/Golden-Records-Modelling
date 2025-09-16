CREATE OR ALTER PROCEDURE dbo.sp_InsertCustomerIncremental
(
    @ClientNo INT,
    @CustomerKey INT,
    @Name NVARCHAR(255),
    @CustomerType NVARCHAR(100),
    @Phone NVARCHAR(50),
    @Email NVARCHAR(255),
    @NationalID NVARCHAR(50),
    @TIN NVARCHAR(50),
    @Location NVARCHAR(100)
)
AS
BEGIN
    -- Temporarily allow explicit inserts into the identity column
    SET IDENTITY_INSERT Bronze.CustomerStage ON;

    INSERT INTO Bronze.CustomerStage (ClientNo, CustomerKey, Name, CustomerType, Phone, Email, NationalID, TIN, Location)
    VALUES (@ClientNo, @CustomerKey, @Name, @CustomerType, @Phone, @Email, @NationalID, @TIN, @Location);

    -- Turn IDENTITY_INSERT back off immediately
    SET IDENTITY_INSERT Bronze.CustomerStage OFF;

    -- Compute surrogates for the new record
    UPDATE Bronze.CustomerStage
    SET FullSurrogate = CONCAT_WS('_',
        ISNULL(Name,''), ISNULL(CustomerType,''), dbo.RemoveNonDigits(ISNULL(Phone,'')),
        LOWER(LTRIM(RTRIM(ISNULL(Email,'')))), ISNULL(NationalID,''), ISNULL(TIN,''), LOWER(ISNULL(Location,''))),
        NormalizedSurrogate = dbo.NormalizeFullSurrogate(Name, Email, Phone, NationalID, TIN, Location, CustomerType)
    WHERE ClientNo = @ClientNo;
END
GO



--2. Incremental Candidate Generation

--Only compare the new record(s) with existing ones.

--Append to CandidatePairs & FuzzyResults.

CREATE OR ALTER PROCEDURE dbo.sp_ProcessNewCustomer
(
    @ClientNo INT
)
AS
BEGIN
    ------------------------------------------------
    -- Candidate Pairs (New record vs existing)
    ------------------------------------------------
    INSERT INTO Bronze.CandidatePairs
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
    FROM Bronze.CustomerStage a
    JOIN Bronze.CustomerStage b ON a.ClientNo = @ClientNo AND b.ClientNo <> @ClientNo
    WHERE
         (ISNULL(a.NationalID,'') <> '' AND a.NationalID = b.NationalID)
      OR (ISNULL(a.TIN,'') <> '' AND a.TIN = b.TIN)
      OR (LOWER(ISNULL(a.Email,'')) <> '' AND LOWER(ISNULL(a.Email,'')) = LOWER(ISNULL(b.Email,'')))
      OR (dbo.RemoveNonDigits(ISNULL(a.Phone,'')) <> '' AND dbo.RemoveNonDigits(ISNULL(a.Phone,'')) = dbo.RemoveNonDigits(ISNULL(b.Phone,'')))
      OR (LEFT(a.NormalizedSurrogate, 20) = LEFT(b.NormalizedSurrogate, 20));

    ------------------------------------------------
    -- Fuzzy Results (only for new record comparisons)
    ------------------------------------------------
    INSERT INTO Bronze.FuzzyResults
    SELECT 
        cp.ClientNoA, cp.ClientNoB, cp.UnifiedA, cp.UnifiedB,
        cp.FullA, cp.FullB, cp.NormSurrogateA, cp.NormSurrogateB,
        cp.NationalIDA, cp.NationalIDB, cp.TINA, cp.TINB,
        cp.EmailA, cp.EmailB, cp.PhoneA, cp.PhoneB,
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
            END AS DECIMAL(5,2)),
        ExactNationalID = CASE WHEN cp.NationalIDA IS NOT NULL AND cp.NationalIDA = cp.NationalIDB THEN 1 ELSE 0 END,
        ExactTIN        = CASE WHEN cp.TINA IS NOT NULL AND cp.TINA = cp.TINB THEN 1 ELSE 0 END,
        ExactEmail      = CASE WHEN cp.EmailA <> '' AND cp.EmailA = cp.EmailB THEN 1 ELSE 0 END,
        ExactPhone      = CASE WHEN cp.PhoneA <> '' AND cp.PhoneA = cp.PhoneB THEN 1 ELSE 0 END
    FROM Bronze.CandidatePairs cp
    WHERE (cp.ClientNoA = @ClientNo OR cp.ClientNoB = @ClientNo);
END
GO
-----------------------------------------------------------------------

CREATE OR ALTER PROCEDURE dbo.sp_MergeIntoClusters
(
    @ClientNo INT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ClusterID INT;
    DECLARE @BestMatchPercent DECIMAL(5,2);

    ------------------------------------------------
    -- Find the best cluster match based on FuzzyResults
    ------------------------------------------------
    SELECT TOP 1 
        @ClusterID = cc.RootClientNo,
        @BestMatchPercent = fr.MatchPercent
    FROM Bronze.FuzzyResults fr
    JOIN Bronze.CustomerClusters cc 
        ON (fr.ClientNoA = cc.RootClientNo OR fr.ClientNoB = cc.RootClientNo)
    WHERE (fr.ClientNoA = @ClientNo OR fr.ClientNoB = @ClientNo)
      AND fr.MatchPercent >= 70
    ORDER BY fr.MatchPercent DESC;

    ------------------------------------------------
    -- If no match → create a new cluster ID
    ------------------------------------------------
    IF @ClusterID IS NULL
    BEGIN
        -- Option 1: use ClientNo as cluster root
        SET @ClusterID = @ClientNo;
        SET @BestMatchPercent = 100; -- self = perfect match
    END

    ------------------------------------------------
    -- Insert new record into CustomerClusters
    ------------------------------------------------
    INSERT INTO Bronze.CustomerClusters (ClusterRow, RootClientNo, PossibleMatchClientNo, MatchPercent)
    SELECT ISNULL(MAX(ClusterRow), 0) + 1, @ClusterID, @ClientNo, @BestMatchPercent
    FROM Bronze.CustomerClusters;

    ------------------------------------------------
    -- Update CustomerMaster aggregation
    ------------------------------------------------
    MERGE Bronze.CustomerMaster AS tgt
    USING (
        SELECT @ClusterID AS CustomerUnifiedID
    ) src
    ON tgt.CustomerUnifiedID = src.CustomerUnifiedID
    WHEN MATCHED THEN
        UPDATE SET SourceClientNos = 
            CASE 
                WHEN CHARINDEX(CAST(@ClientNo AS VARCHAR(20)), tgt.SourceClientNos) > 0 
                THEN tgt.SourceClientNos  -- already exists, no duplicate
                ELSE tgt.SourceClientNos + ',' + CAST(@ClientNo AS VARCHAR(20)) 
            END
    WHEN NOT MATCHED THEN
        INSERT (MasterCustomerID, CustomerUnifiedID, SourceClientNos)
        VALUES (
            (SELECT ISNULL(MAX(MasterCustomerID),0)+1 FROM Bronze.CustomerMaster),
            @ClusterID,
            CAST(@ClientNo AS VARCHAR(20))
        );
END
GO

