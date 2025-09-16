--EXEC dbo.sp_InsertCustomerIncremental
--    @ClientNo = 301,
--    @CustomerKey = 5,
--    @Name = 'Unknown Person',
--    @CustomerType = 'Retail',
--    @Phone = NULL,
--    @Email = NULL,
--    @NationalID = NULL,
--    @TIN = NULL,
--    @Location = 'Unknown';

-- Check the new record and its computed surrogates
SELECT TOP 10 *
FROM Bronze.CustomerStage
ORDER BY ClientNo DESC;



SELECT TOP 10 *
FROM Bronze.FuzzyResults
ORDER BY ClientNoA DESC, MatchPercent DESC;

SELECT TOP 10 *
FROM Bronze.CustomerClusters
ORDER BY MatchPercent desc, ClusterRow DESC;

SELECT TOP 10 *
FROM Silver.CustomerMaster
ORDER BY MasterCustomerID DESC;


