-- 04_seed_workforce_plan.sql: target headcount per department (sum 155; the CEO is outside the departments).
-- Technology (48 vs 45 employees) and Sales (37 vs 35) are planned above their current headcount, so the report shows
-- 2 departments below target (3 of 5 at target). Employee data (150 in departments) is not changed by this script.
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -i sql/04_seed_workforce_plan.sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
BEGIN TRANSACTION;

DELETE FROM dbo.DepartmentWorkforcePlan;
-- Restart IDs at 1 (a never-used identity needs seed 1, a used one needs 0)
DECLARE @seed int = CASE WHEN EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.DepartmentWorkforcePlan') AND last_value IS NULL) THEN 1 ELSE 0 END;
DBCC CHECKIDENT ('dbo.DepartmentWorkforcePlan', RESEED, @seed) WITH NO_INFOMSGS;

INSERT INTO dbo.DepartmentWorkforcePlan (OrganizationUnitID, TargetHeadcount)
SELECT u.OrganizationUnitID, t.Target
FROM (VALUES (N'Technology',48),(N'Finance',25),(N'Human Resources',20),(N'Sales',37),(N'Customer Experience',25)) t(UnitName, Target)
JOIN dbo.OrganizationUnits u ON u.UnitName = t.UnitName AND u.UnitType = 'Department';

COMMIT TRANSACTION;
GO

-- Check: 5 targets, sum 155
SELECT u.UnitName, w.TargetHeadcount
FROM dbo.DepartmentWorkforcePlan w JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = w.OrganizationUnitID
ORDER BY w.WorkforcePlanID;
SELECT COUNT(*) AS Departments, SUM(TargetHeadcount) AS TotalTarget FROM dbo.DepartmentWorkforcePlan;
GO
