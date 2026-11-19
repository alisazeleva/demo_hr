-- 13_create_reporting_views.sql: reporting views for Power BI (PLAN.md, Power BI plan, Model).
-- Every view is CREATE OR ALTER VIEW in its own batch, so the script can be re-run. No view uses GETDATE():
-- the reference date lives in one place, dbo.vw_ReferenceDate, and all other views read it from there.
-- Star schema for Power BI: dimensions vw_DimDepartment, vw_DimPosition, vw_DimEmployee, vw_DimManager, vw_DimLeaveType;
-- facts vw_JobHistory, vw_CompensationHistory, vw_PerformanceReviews, vw_LeaveDays, vw_LeaveRequests, vw_FactWorkforcePlan carry keys, dates and
-- measures. Names are repeated only where an event needs its own label (position, department and manager at the time of a job change).
-- vw_EmployeeCurrent and vw_OrgHierarchy stay as flat views for SQL checks and ad-hoc queries (the Power BI model does not load them).
-- Run with -I (quoted identifiers ON):
--   sqlcmd -S ".\SQLEXPRESS" -E -C -b -I -d DemoHR -f 65001 -i sql/13_create_reporting_views.sql
SET NOCOUNT ON;
GO

-- ====================================================================== reference date (the only place it is written)
CREATE OR ALTER VIEW dbo.vw_ReferenceDate
AS
SELECT CAST('2026-11-16' AS date) AS ReferenceDate;
GO

-- ====================================================================== reporting tree: depth, path from the CEO, manager chain
CREATE OR ALTER VIEW dbo.vw_OrgHierarchy
AS
WITH tree AS (
    SELECT e.EmployeeID, 0 AS Depth,
           CAST('/' + CAST(e.EmployeeID AS varchar(10)) + '/' AS varchar(200)) AS PathIDs,
           CAST(e.FirstName + N' ' + e.LastName AS nvarchar(1000)) AS FullName,
           CAST(e.FirstName + N' ' + e.LastName AS nvarchar(1000)) AS PathNames,
           CAST(NULL AS nvarchar(1000)) AS ManagerChain
    FROM dbo.Employees e WHERE e.ManagerEmployeeID IS NULL
    UNION ALL
    SELECT c.EmployeeID, t.Depth + 1,
           CAST(t.PathIDs + CAST(c.EmployeeID AS varchar(10)) + '/' AS varchar(200)),
           CAST(c.FirstName + N' ' + c.LastName AS nvarchar(1000)),
           CAST(t.PathNames + N' > ' + c.FirstName + N' ' + c.LastName AS nvarchar(1000)),
           CAST(t.FullName + CASE WHEN t.ManagerChain IS NULL THEN N'' ELSE N' > ' + t.ManagerChain END AS nvarchar(1000))
    FROM dbo.Employees c JOIN tree t ON c.ManagerEmployeeID = t.EmployeeID)
SELECT e.EmployeeID, e.EmployeeNumber, t.FullName AS EmployeeName, p.PositionTitle, p.JobLevel, p.JobLevelRank,
       u.UnitName AS Department,
       e.ManagerEmployeeID, m.FirstName + N' ' + m.LastName AS ManagerName,
       t.Depth, t.PathIDs, t.PathNames AS PathFromCEO, t.ManagerChain,
       (SELECT COUNT(*) FROM dbo.Employees d WHERE d.ManagerEmployeeID = e.EmployeeID) AS DirectReports
FROM tree t
JOIN dbo.Employees e ON e.EmployeeID = t.EmployeeID
JOIN dbo.Positions p ON p.PositionID = e.PositionID
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = e.OrganizationUnitID
LEFT JOIN dbo.Employees m ON m.EmployeeID = e.ManagerEmployeeID;
GO

-- ====================================================================== one row per employee
CREATE OR ALTER VIEW dbo.vw_EmployeeCurrent
AS
SELECT e.EmployeeID, e.EmployeeNumber, e.FirstName, e.LastName,
       e.FirstName + N' ' + e.LastName AS FullName,
       e.Gender, e.DateOfBirth,
       DATEDIFF(YEAR, e.DateOfBirth, r.ReferenceDate)
         - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, e.DateOfBirth, r.ReferenceDate), e.DateOfBirth) > r.ReferenceDate THEN 1 ELSE 0 END AS Age,
       e.Nationality, e.NativeLanguage, e.HireDate,
       CAST(DATEDIFF(DAY, e.HireDate, r.ReferenceDate) / 365.25 AS decimal(5,2)) AS TenureYears,
       e.EmailAddress,
       p.PositionID, p.PositionTitle, p.JobFamily, p.JobLevel, p.JobLevelRank, p.IsManagementPosition,
       u.OrganizationUnitID AS DepartmentID, u.UnitName AS Department,
       e.ManagerEmployeeID, m.FirstName + N' ' + m.LastName AS ManagerName,
       (SELECT COUNT(*) FROM dbo.Employees d WHERE d.ManagerEmployeeID = e.EmployeeID) AS DirectReports,
       c.BaseSalary AS CurrentSalary, c.Currency,
       rv.OverallRating AS LatestRating, rv.ReviewDate AS LatestReviewDate, rv.PerformanceLevel AS LatestPerformanceLevel,
       e.ProfileImageFileName,
       oh.Depth AS OrgDepth, oh.PathIDs, oh.PathFromCEO, oh.ManagerChain      -- reporting tree, from vw_OrgHierarchy (created above it)
FROM dbo.Employees e
CROSS JOIN dbo.vw_ReferenceDate r
JOIN dbo.Positions p ON p.PositionID = e.PositionID
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = e.OrganizationUnitID
LEFT JOIN dbo.Employees m ON m.EmployeeID = e.ManagerEmployeeID
LEFT JOIN dbo.EmployeeCompensationHistory c ON c.EmployeeID = e.EmployeeID AND c.EndDate IS NULL
LEFT JOIN dbo.vw_OrgHierarchy oh ON oh.EmployeeID = e.EmployeeID
OUTER APPLY (SELECT TOP (1) x.OverallRating, x.ReviewDate, x.PerformanceLevel
             FROM dbo.PerformanceReviews x WHERE x.EmployeeID = e.EmployeeID ORDER BY x.ReviewPeriodEnd DESC) rv;
GO

-- ====================================================================== dimensions
CREATE OR ALTER VIEW dbo.vw_DimDepartment
AS
SELECT u.OrganizationUnitID AS DepartmentID, u.UnitName AS Department, u.UnitType AS DepartmentType
FROM dbo.OrganizationUnits u;
GO

CREATE OR ALTER VIEW dbo.vw_DimPosition
AS
SELECT p.PositionID, p.PositionTitle, p.JobFamily, p.JobLevel, p.JobLevelRank, p.IsManagementPosition
FROM dbo.Positions p;
GO

-- one row per employee: who they are plus current keys (position, department, manager) and current-state values
CREATE OR ALTER VIEW dbo.vw_DimEmployee
AS
SELECT e.EmployeeID, e.EmployeeNumber, e.FirstName, e.LastName,
       e.FirstName + N' ' + e.LastName AS FullName,
       e.Gender, e.DateOfBirth,
       DATEDIFF(YEAR, e.DateOfBirth, r.ReferenceDate)
         - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, e.DateOfBirth, r.ReferenceDate), e.DateOfBirth) > r.ReferenceDate THEN 1 ELSE 0 END AS Age,
       e.Nationality, e.NativeLanguage, e.HireDate,
       CAST(DATEDIFF(DAY, e.HireDate, r.ReferenceDate) / 365.25 AS decimal(5,2)) AS TenureYears,
       e.EmailAddress,
       e.PositionID, e.OrganizationUnitID AS DepartmentID, e.ManagerEmployeeID,
       (SELECT COUNT(*) FROM dbo.Employees d WHERE d.ManagerEmployeeID = e.EmployeeID) AS DirectReports,
       c.BaseSalary AS CurrentSalary, c.Currency,
       rv.OverallRating AS LatestRating, rv.ReviewDate AS LatestReviewDate, rv.PerformanceLevel AS LatestPerformanceLevel,
       e.ProfileImageFileName,
       oh.Depth AS OrgDepth, oh.PathIDs, oh.PathFromCEO, oh.ManagerChain
FROM dbo.Employees e
CROSS JOIN dbo.vw_ReferenceDate r
LEFT JOIN dbo.EmployeeCompensationHistory c ON c.EmployeeID = e.EmployeeID AND c.EndDate IS NULL
LEFT JOIN dbo.vw_OrgHierarchy oh ON oh.EmployeeID = e.EmployeeID
OUTER APPLY (SELECT TOP (1) x.OverallRating, x.ReviewDate, x.PerformanceLevel
             FROM dbo.PerformanceReviews x WHERE x.EmployeeID = e.EmployeeID ORDER BY x.ReviewPeriodEnd DESC) rv;
GO

-- managers only: the manager role of an employee (one row per employee who has direct reports)
CREATE OR ALTER VIEW dbo.vw_DimManager
AS
SELECT m.EmployeeID AS ManagerEmployeeID, m.EmployeeNumber AS ManagerNumber,
       m.FirstName + N' ' + m.LastName AS ManagerName
FROM dbo.Employees m
WHERE EXISTS (SELECT 1 FROM dbo.Employees d WHERE d.ManagerEmployeeID = m.EmployeeID);
GO

CREATE OR ALTER VIEW dbo.vw_DimLeaveType
AS
SELECT t.LeaveTypeID, t.LeaveTypeName AS LeaveType, t.IsPaid
FROM dbo.LeaveTypes t;
GO

-- ====================================================================== job history: keys, dates, flags, and the labels of the old and new position, department and manager
CREATE OR ALTER VIEW dbo.vw_JobHistory
AS
WITH h AS (
    SELECT j.*,
           LAG(j.PositionID)         OVER (PARTITION BY j.EmployeeID ORDER BY j.EffectiveDate) AS PrevPositionID,
           LAG(j.OrganizationUnitID) OVER (PARTITION BY j.EmployeeID ORDER BY j.EffectiveDate) AS PrevUnitID,
           LAG(j.ManagerEmployeeID)  OVER (PARTITION BY j.EmployeeID ORDER BY j.EffectiveDate) AS PrevManagerID
    FROM dbo.EmployeeJobHistory j)
SELECT h.JobHistoryID, h.EmployeeID,
       h.EffectiveDate, h.EndDate, CAST(CASE WHEN h.EndDate IS NULL THEN 1 ELSE 0 END AS bit) AS IsCurrent,
       h.ChangeType, h.Reason,
       CAST(CASE WHEN h.ChangeType IN ('Promotion', 'Promotion + Department Transfer') THEN 1 ELSE 0 END AS bit) AS IsPromotion,
       CAST(CASE WHEN h.ChangeType IN ('Department Transfer', 'Promotion + Department Transfer') THEN 1 ELSE 0 END AS bit) AS IsDepartmentTransfer,
       -- new (this record)
       h.PositionID, h.OrganizationUnitID AS DepartmentID, h.ManagerEmployeeID AS ManagerID,
       p.PositionTitle, u.UnitName AS Department, m.FirstName + N' ' + m.LastName AS ManagerName,
       -- previous (the record before it; NULL for the first record)
       h.PrevPositionID, h.PrevUnitID AS PrevDepartmentID, h.PrevManagerID,
       pp.PositionTitle AS PrevPositionTitle, pu.UnitName AS PrevDepartment, pm.FirstName + N' ' + pm.LastName AS PrevManagerName
FROM h
JOIN dbo.Positions p ON p.PositionID = h.PositionID
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = h.OrganizationUnitID
LEFT JOIN dbo.Employees m ON m.EmployeeID = h.ManagerEmployeeID
LEFT JOIN dbo.Positions pp ON pp.PositionID = h.PrevPositionID
LEFT JOIN dbo.OrganizationUnits pu ON pu.OrganizationUnitID = h.PrevUnitID
LEFT JOIN dbo.Employees pm ON pm.EmployeeID = h.PrevManagerID;
GO

-- ====================================================================== salary periods with the previous salary and the change
CREATE OR ALTER VIEW dbo.vw_CompensationHistory
AS
WITH c AS (
    SELECT x.*, LAG(x.BaseSalary) OVER (PARTITION BY x.EmployeeID ORDER BY x.EffectiveDate) AS PrevSalary
    FROM dbo.EmployeeCompensationHistory x)
SELECT c.CompensationHistoryID, c.EmployeeID,
       c.EffectiveDate, c.EndDate, CAST(CASE WHEN c.EndDate IS NULL THEN 1 ELSE 0 END AS bit) AS IsCurrent,
       c.BaseSalary AS Salary, c.Currency, c.PayFrequency,
       c.PrevSalary AS PreviousSalary,
       c.BaseSalary - c.PrevSalary AS ChangeAmount,
       CAST(100.0 * (c.BaseSalary / c.PrevSalary - 1) AS decimal(6,2)) AS ChangePct,
       c.ChangeReason AS Reason
FROM c;
GO

-- ====================================================================== reviews: reviewer, and the position and department on 31 December of the period (keys)
CREATE OR ALTER VIEW dbo.vw_PerformanceReviews
AS
SELECT r.PerformanceReviewID, r.EmployeeID,
       r.ReviewerEmployeeID AS ReviewerID, rv.FirstName + N' ' + rv.LastName AS ReviewerName,
       j.PositionID, j.OrganizationUnitID AS DepartmentID,
       YEAR(r.ReviewPeriodEnd) AS ReviewYear, r.ReviewPeriodStart, r.ReviewPeriodEnd, r.ReviewDate,
       r.OverallRating AS Rating, r.PerformanceLevel AS Level, r.Comments,
       CAST(CASE WHEN r.ReviewDate > DATEADD(MONTH, -12, d.ReferenceDate) AND r.ReviewDate <= d.ReferenceDate THEN 1 ELSE 0 END AS bit) AS IsRecentReview
FROM dbo.PerformanceReviews r
CROSS JOIN dbo.vw_ReferenceDate d
JOIN dbo.Employees rv ON rv.EmployeeID = r.ReviewerEmployeeID
JOIN dbo.EmployeeJobHistory j ON j.EmployeeID = r.EmployeeID AND j.EffectiveDate <= r.ReviewPeriodEnd AND (j.EndDate IS NULL OR j.EndDate > r.ReviewPeriodEnd);
GO

-- ====================================================================== one row per working day of every Approved leave
CREATE OR ALTER VIEW dbo.vw_LeaveDays
AS
SELECT l.LeaveID, l.EmployeeID,
       j.OrganizationUnitID AS DepartmentID,           -- department on that day, from job history
       l.LeaveTypeID,
       d.LeaveDate,
       CAST(CASE WHEN d.LeaveDate <= r.ReferenceDate THEN 1 ELSE 0 END AS bit) AS IsOnOrBeforeReferenceDate
FROM dbo.EmployeeLeaves l
CROSS JOIN dbo.vw_ReferenceDate r
CROSS APPLY (   -- every calendar day from start to end (up to 1000 days), then only working days
    SELECT DATEADD(DAY, a.v + 10 * b.v + 100 * c.v, l.StartDate) AS LeaveDate
    FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) a(v)
    CROSS JOIN (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) b(v)
    CROSS JOIN (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) c(v)
    WHERE a.v + 10 * b.v + 100 * c.v <= DATEDIFF(DAY, l.StartDate, l.EndDate)) d
JOIN dbo.EmployeeJobHistory j ON j.EmployeeID = l.EmployeeID AND j.EffectiveDate <= d.LeaveDate AND (j.EndDate IS NULL OR j.EndDate > d.LeaveDate)
WHERE l.Status = 'Approved'
  AND DATEDIFF(DAY, '19000101', d.LeaveDate) % 7 < 5                                   -- Monday-Friday (1900-01-01 was a Monday)
  AND NOT EXISTS (SELECT 1 FROM dbo.PublicHolidays h WHERE h.HolidayDate = d.LeaveDate);
GO

-- ====================================================================== leave requests: one row per request of any status (pending and rejected included)
CREATE OR ALTER VIEW dbo.vw_LeaveRequests
AS
SELECT l.LeaveID, l.EmployeeID,
       j.OrganizationUnitID AS DepartmentID,           -- department on the start date, from job history
       l.LeaveTypeID, l.Status, l.StartDate, l.EndDate
FROM dbo.EmployeeLeaves l
JOIN dbo.EmployeeJobHistory j ON j.EmployeeID = l.EmployeeID AND j.EffectiveDate <= l.StartDate AND (j.EndDate IS NULL OR j.EndDate > l.StartDate);
GO

-- ====================================================================== workforce plan: target headcount per department (fact for the star)
CREATE OR ALTER VIEW dbo.vw_FactWorkforcePlan
AS
SELECT w.OrganizationUnitID AS DepartmentID, w.TargetHeadcount
FROM dbo.DepartmentWorkforcePlan w;
GO

-- ====================================================================== headcount against the workforce plan
CREATE OR ALTER VIEW dbo.vw_DepartmentHeadcountVsTarget
AS
SELECT u.OrganizationUnitID AS DepartmentID, u.UnitName AS Department,
       w.TargetHeadcount, COUNT(e.EmployeeID) AS ActualHeadcount,
       COUNT(e.EmployeeID) - w.TargetHeadcount AS Difference,
       CAST(100.0 * COUNT(e.EmployeeID) / w.TargetHeadcount AS decimal(5,1)) AS PctOfTarget
FROM dbo.DepartmentWorkforcePlan w
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = w.OrganizationUnitID
LEFT JOIN dbo.Employees e ON e.OrganizationUnitID = u.OrganizationUnitID
GROUP BY u.OrganizationUnitID, u.UnitName, w.TargetHeadcount;
GO

-- ====================================================================== row counts
SELECT 'vw_ReferenceDate' AS ViewName, COUNT(*) AS [Rows], 1 AS Expected FROM dbo.vw_ReferenceDate
UNION ALL SELECT 'vw_EmployeeCurrent', COUNT(*), 151 FROM dbo.vw_EmployeeCurrent
UNION ALL SELECT 'vw_JobHistory', COUNT(*), (SELECT COUNT(*) FROM dbo.EmployeeJobHistory) FROM dbo.vw_JobHistory
UNION ALL SELECT 'vw_CompensationHistory', COUNT(*), (SELECT COUNT(*) FROM dbo.EmployeeCompensationHistory) FROM dbo.vw_CompensationHistory
UNION ALL SELECT 'vw_PerformanceReviews', COUNT(*), (SELECT COUNT(*) FROM dbo.PerformanceReviews) FROM dbo.vw_PerformanceReviews
UNION ALL SELECT 'vw_LeaveDays', COUNT(*), NULL FROM dbo.vw_LeaveDays
UNION ALL SELECT 'vw_LeaveRequests', COUNT(*), (SELECT COUNT(*) FROM dbo.EmployeeLeaves) FROM dbo.vw_LeaveRequests
UNION ALL SELECT 'vw_DepartmentHeadcountVsTarget', COUNT(*), 5 FROM dbo.vw_DepartmentHeadcountVsTarget
UNION ALL SELECT 'vw_OrgHierarchy', COUNT(*), 151 FROM dbo.vw_OrgHierarchy
UNION ALL SELECT 'vw_DimDepartment', COUNT(*), 6 FROM dbo.vw_DimDepartment
UNION ALL SELECT 'vw_DimPosition', COUNT(*), (SELECT COUNT(*) FROM dbo.Positions) FROM dbo.vw_DimPosition
UNION ALL SELECT 'vw_DimEmployee', COUNT(*), 151 FROM dbo.vw_DimEmployee
UNION ALL SELECT 'vw_DimManager', COUNT(*), 36 FROM dbo.vw_DimManager
UNION ALL SELECT 'vw_DimLeaveType', COUNT(*), (SELECT COUNT(*) FROM dbo.LeaveTypes) FROM dbo.vw_DimLeaveType
UNION ALL SELECT 'vw_FactWorkforcePlan', COUNT(*), 5 FROM dbo.vw_FactWorkforcePlan;
GO
