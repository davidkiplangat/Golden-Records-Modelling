    SELECT 
        c.RootClientNo,
        STRING_AGG(c.PossibleMatchClientNo, ',') AS SourceClientNos,
		STRING_AGG(c.MatchPercent, ',') AS PossibilityScores,
        COUNT(*) AS ClusterSize
	FROM Bronze.CustomerClusters c
    GROUP BY c.RootClientNo
	ORDER BY COUNT(*) DESC