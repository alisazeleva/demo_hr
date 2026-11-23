-- 07_validate_hierarchy.sql: read-only checks of the reporting structure. Changes nothing.
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -f 65001 -i sql/07_validate_hierarchy.sql
SET NOCOUNT ON;

-- Everything is collected in one result: Check, Violations (expect 0 unless noted), Status
CREATE TABLE #Result (Ord int IDENTITY(1,1), CheckName nvarchar(120), Violations int, Expected nvarchar(20));

-- 1. Exactly one CEO, with no manager; nobody else without a manager
INSERT INTO #Result (CheckName, Violations, Expected) VALUES
(N'Exactly one CEO position holder',
 ABS(1 - (SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID WHERE p.JobLevelRank = 1)), N'0'),
(N'Employees without a manager other than the CEO',
 (SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID WHERE e.ManagerEmployeeID IS NULL AND p.JobLevelRank <> 1), N'0'),
(N'CEO has a manager',
 (SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID WHERE e.ManagerEmployeeID IS NOT NULL AND p.JobLevelRank = 1), N'0'),
-- 2. No self-reports, manager exists
(N'Employees who report to themselves',
 (SELECT COUNT(*) FROM dbo.Employees WHERE ManagerEmployeeID = EmployeeID), N'0'),
-- 3. Manager level strictly higher than the report's (lower rank number)
(N'Manager level not strictly higher than the report',
 (SELECT COUNT(*) FROM dbo.Employees e
  JOIN dbo.Positions pe ON pe.PositionID = e.PositionID
  JOIN dbo.Employees m ON m.EmployeeID = e.ManagerEmployeeID
  JOIN dbo.Positions pm ON pm.PositionID = m.PositionID
  WHERE pm.JobLevelRank >= pe.JobLevelRank), N'0'),
-- 4. Manager hired before the report; manager number lower than the report's (rank order)
(N'Manager hired on or after the report''s hire date',
 (SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.Employees m ON m.EmployeeID = e.ManagerEmployeeID WHERE m.HireDate >= e.HireDate), N'0'),
(N'Manager number not lower than the report''s number',
 (SELECT COUNT(*) FROM dbo.Employees WHERE ManagerEmployeeID >= EmployeeID), N'0'),
-- 5. Reporting-line pattern from PLAN.md: C-Level -> CEO, VP -> C-Level, Director -> VP or C-Level, Manager -> Director, staff -> Manager
(N'Reporting line breaks the level pattern',
 (SELECT COUNT(*) FROM dbo.Employees e
  JOIN dbo.Positions pe ON pe.PositionID = e.PositionID
  JOIN dbo.Employees m ON m.EmployeeID = e.ManagerEmployeeID
  JOIN dbo.Positions pm ON pm.PositionID = m.PositionID
  WHERE NOT ((pe.JobLevelRank = 2 AND pm.JobLevelRank = 1)
          OR (pe.JobLevelRank = 3 AND pm.JobLevelRank = 2)
          OR (pe.JobLevelRank = 4 AND pm.JobLevelRank IN (2, 3))
          OR (pe.JobLevelRank = 5 AND pm.JobLevelRank = 4)
          OR (pe.JobLevelRank >= 6 AND pm.JobLevelRank = 5))), N'0'),
-- 6. Directors report to a VP when their department has one
(N'Directors reporting to a C-Level although a VP exists in the department',
 (SELECT COUNT(*) FROM dbo.Employees e
  JOIN dbo.Positions pe ON pe.PositionID = e.PositionID AND pe.JobLevelRank = 4
  JOIN dbo.Employees m ON m.EmployeeID = e.ManagerEmployeeID
  JOIN dbo.Positions pm ON pm.PositionID = m.PositionID AND pm.JobLevelRank = 2
  WHERE EXISTS (SELECT 1 FROM dbo.Employees v JOIN dbo.Positions pv ON pv.PositionID = v.PositionID
                WHERE pv.JobLevelRank = 3 AND v.OrganizationUnitID = e.OrganizationUnitID)), N'0'),
-- 7. Manager is in the same department, except C-Levels who report to the CEO
(N'Manager in a different department (C-Level to CEO excepted)',
 (SELECT COUNT(*) FROM dbo.Employees e
  JOIN dbo.Positions pe ON pe.PositionID = e.PositionID
  JOIN dbo.Employees m ON m.EmployeeID = e.ManagerEmployeeID
  WHERE pe.JobLevelRank <> 2 AND m.OrganizationUnitID <> e.OrganizationUnitID), N'0'),
-- 8. Employee department equals position department
(N'Employee department differs from position department',
 (SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID WHERE p.OrganizationUnitID <> e.OrganizationUnitID), N'0'),
-- 9. Every manager-level position (rank 1 to 5) has at least one direct report
(N'Management positions (CEO to Manager) with no direct reports',
 (SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID
  WHERE p.JobLevelRank <= 5 AND NOT EXISTS (SELECT 1 FROM dbo.Employees r WHERE r.ManagerEmployeeID = e.EmployeeID)), N'0'),
-- 10. Non-management positions have no direct reports
(N'Non-management employees with direct reports',
 (SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID
  WHERE p.IsManagementPosition = 0 AND EXISTS (SELECT 1 FROM dbo.Employees r WHERE r.ManagerEmployeeID = e.EmployeeID)), N'0');

-- 11. No cycles: walk down from the CEO; every employee must be reached exactly once, depth stays small
;WITH tree AS (
    SELECT e.EmployeeID, 0 AS Depth, CAST('/' + CAST(e.EmployeeID AS varchar(10)) + '/' AS varchar(400)) AS Path
    FROM dbo.Employees e WHERE e.ManagerEmployeeID IS NULL
    UNION ALL
    SELECT c.EmployeeID, t.Depth + 1, CAST(t.Path + CAST(c.EmployeeID AS varchar(10)) + '/' AS varchar(400))
    FROM dbo.Employees c JOIN tree t ON c.ManagerEmployeeID = t.EmployeeID
    WHERE t.Depth < 10 AND t.Path NOT LIKE '%/' + CAST(c.EmployeeID AS varchar(10)) + '/%'
)
INSERT INTO #Result (CheckName, Violations, Expected)
SELECT N'Employees not reachable from the CEO (cycle or orphan)', (SELECT COUNT(*) FROM dbo.Employees) - COUNT(DISTINCT EmployeeID), N'0' FROM tree
UNION ALL
SELECT N'Employees reached more than once (cycle)', COUNT(*) - COUNT(DISTINCT EmployeeID), N'0' FROM tree
UNION ALL
SELECT N'Reporting depth deeper than 5 levels below the CEO', COUNT(*), N'0' FROM tree WHERE Depth > 5;

SELECT Ord AS [#], CheckName, Violations, CASE WHEN Violations = 0 THEN 'PASS' ELSE 'FAIL' END AS Status FROM #Result ORDER BY Ord;
SELECT SUM(CASE WHEN Violations = 0 THEN 1 ELSE 0 END) AS ChecksPassed, SUM(CASE WHEN Violations <> 0 THEN 1 ELSE 0 END) AS ChecksFailed FROM #Result;

-- Information: reports per manager level, and per management employee
SELECT p.JobLevel AS ManagerLevel, COUNT(*) AS Managers, MIN(x.Reports) AS MinReports, MAX(x.Reports) AS MaxReports, CAST(AVG(1.0 * x.Reports) AS decimal(4,1)) AS AvgReports
FROM dbo.Employees e
JOIN dbo.Positions p ON p.PositionID = e.PositionID
CROSS APPLY (SELECT COUNT(*) AS Reports FROM dbo.Employees r WHERE r.ManagerEmployeeID = e.EmployeeID) x
WHERE p.JobLevelRank <= 5
GROUP BY p.JobLevelRank, p.JobLevel ORDER BY p.JobLevelRank;

DROP TABLE #Result;
GO
