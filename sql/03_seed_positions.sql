-- 03_seed_positions.sql: the 67-position catalogue.
-- The Holders column exists only in this script (temp table) to check the planned headcount;
-- the schema stores no holder counts.
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -i sql/03_seed_positions.sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
BEGIN TRANSACTION;

DELETE FROM dbo.Positions;
-- Restart IDs at 1 (a never-used identity needs seed 1, a used one needs 0)
DECLARE @seed int = CASE WHEN EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.Positions') AND last_value IS NULL) THEN 1 ELSE 0 END;
DBCC CHECKIDENT ('dbo.Positions', RESEED, @seed) WITH NO_INFOMSGS;

CREATE TABLE #Cat (
    Ord int IDENTITY(1,1) PRIMARY KEY,
    UnitName nvarchar(100), JobLevel varchar(20), PositionTitle nvarchar(100), JobFamily nvarchar(50), Holders int
);

INSERT INTO #Cat (UnitName, JobLevel, PositionTitle, JobFamily, Holders) VALUES
(N'Acme Corporation','CEO',N'Chief Executive Officer',N'Executive',1),
-- Technology
(N'Technology','C-Level',N'Chief Technology Officer',N'Executive',1),
(N'Technology','VP',N'VP Engineering',N'Engineering',1),
(N'Technology','VP',N'VP Data & IT',N'Data & IT',1),
(N'Technology','Director',N'Director of Software Engineering',N'Engineering',1),
(N'Technology','Director',N'Director of Data & Analytics',N'Data & Analytics',1),
(N'Technology','Director',N'Director of IT Operations',N'IT Operations',1),
(N'Technology','Manager',N'Engineering Manager',N'Engineering',3),
(N'Technology','Manager',N'Data & Analytics Manager',N'Data & Analytics',1),
(N'Technology','Manager',N'IT Operations Manager',N'IT Operations',1),
(N'Technology','Senior',N'Senior Software Engineer',N'Engineering',6),
(N'Technology','Senior',N'Senior Data Analyst',N'Data & Analytics',2),
(N'Technology','Senior',N'Senior Systems Administrator',N'IT Operations',2),
(N'Technology','Professional',N'Software Engineer',N'Engineering',9),
(N'Technology','Professional',N'Data Analyst',N'Data & Analytics',3),
(N'Technology','Professional',N'Systems Administrator',N'IT Operations',3),
(N'Technology','Junior',N'Junior Software Engineer',N'Engineering',5),
(N'Technology','Junior',N'Junior Data Analyst',N'Data & Analytics',2),
(N'Technology','Junior',N'IT Support Specialist',N'IT Operations',2),
-- Finance
(N'Finance','C-Level',N'Chief Financial Officer',N'Executive',1),
(N'Finance','Director',N'Director of FP&A',N'Financial Planning & Analysis',1),
(N'Finance','Director',N'Director of Accounting',N'Accounting',1),
(N'Finance','Manager',N'FP&A Manager',N'Financial Planning & Analysis',1),
(N'Finance','Manager',N'Accounting Manager',N'Accounting',1),
(N'Finance','Manager',N'Treasury & Controls Manager',N'Treasury & Controls',1),
(N'Finance','Senior',N'Senior Financial Analyst',N'Financial Planning & Analysis',3),
(N'Finance','Senior',N'Senior Accountant',N'Accounting',3),
(N'Finance','Professional',N'Financial Analyst',N'Financial Planning & Analysis',4),
(N'Finance','Professional',N'Accountant',N'Accounting',4),
(N'Finance','Junior',N'Junior Financial Analyst',N'Financial Planning & Analysis',2),
(N'Finance','Junior',N'Junior Accountant',N'Accounting',3),
-- Human Resources
(N'Human Resources','C-Level',N'Chief Human Resources Officer',N'Executive',1),
(N'Human Resources','Director',N'Director of People Operations',N'People Operations',1),
(N'Human Resources','Manager',N'Talent Acquisition Manager',N'Talent Acquisition',1),
(N'Human Resources','Manager',N'HR Business Partner Manager',N'HR Business Partnering',1),
(N'Human Resources','Senior',N'Senior HR Business Partner',N'HR Business Partnering',2),
(N'Human Resources','Senior',N'Senior Recruiter',N'Talent Acquisition',2),
(N'Human Resources','Professional',N'HR Business Partner',N'HR Business Partnering',3),
(N'Human Resources','Professional',N'Recruiter',N'Talent Acquisition',3),
(N'Human Resources','Professional',N'HR Specialist',N'People Operations',2),
(N'Human Resources','Junior',N'HR Assistant',N'People Operations',2),
(N'Human Resources','Junior',N'Junior Recruiter',N'Talent Acquisition',2),
-- Sales
(N'Sales','C-Level',N'Chief Revenue Officer',N'Executive',1),
(N'Sales','VP',N'VP Sales',N'Sales Leadership',1),
(N'Sales','Director',N'Director of Enterprise Sales',N'Enterprise Sales',1),
(N'Sales','Director',N'Director of SMB & Partnerships',N'SMB & Partnerships',1),
(N'Sales','Manager',N'Enterprise Sales Manager',N'Enterprise Sales',2),
(N'Sales','Manager',N'SMB Sales Manager',N'SMB & Partnerships',1),
(N'Sales','Manager',N'Partnership Manager',N'SMB & Partnerships',1),
(N'Sales','Senior',N'Senior Account Executive',N'Enterprise Sales',6),
(N'Sales','Senior',N'Senior Sales Operations Analyst',N'Sales Operations',2),
(N'Sales','Professional',N'Account Executive',N'Enterprise Sales',8),
(N'Sales','Professional',N'Sales Operations Analyst',N'Sales Operations',2),
(N'Sales','Professional',N'Partnership Specialist',N'SMB & Partnerships',2),
(N'Sales','Junior',N'Sales Development Representative',N'Enterprise Sales',5),
(N'Sales','Junior',N'Junior Account Executive',N'SMB & Partnerships',2),
-- Customer Experience
(N'Customer Experience','C-Level',N'Chief Customer Officer',N'Executive',1),
(N'Customer Experience','Director',N'Director of Customer Support',N'Customer Support',1),
(N'Customer Experience','Director',N'Director of Customer Success',N'Customer Success',1),
(N'Customer Experience','Manager',N'Support Team Manager',N'Customer Support',2),
(N'Customer Experience','Manager',N'Customer Success Team Manager',N'Customer Success',1),
(N'Customer Experience','Senior',N'Senior Support Specialist',N'Customer Support',3),
(N'Customer Experience','Senior',N'Senior Customer Success Specialist',N'Customer Success',2),
(N'Customer Experience','Professional',N'Support Specialist',N'Customer Support',5),
(N'Customer Experience','Professional',N'Customer Success Specialist',N'Customer Success',4),
(N'Customer Experience','Junior',N'Junior Support Agent',N'Customer Support',3),
(N'Customer Experience','Junior',N'Junior Customer Success Associate',N'Customer Success',2);

INSERT INTO dbo.Positions (PositionTitle, JobFamily, JobLevel, JobLevelRank, IsManagementPosition, IsExecutivePosition, OrganizationUnitID)
SELECT c.PositionTitle, c.JobFamily, c.JobLevel, r.JobLevelRank,
       CASE WHEN r.JobLevelRank <= 5 THEN 1 ELSE 0 END,   -- CEO ... Manager
       CASE WHEN r.JobLevelRank <= 3 THEN 1 ELSE 0 END,   -- CEO, C-Level, VP
       u.OrganizationUnitID
FROM #Cat c
JOIN (VALUES ('CEO',1),('C-Level',2),('VP',3),('Director',4),('Manager',5),('Senior',6),('Professional',7),('Junior',8)) r(JobLevel, JobLevelRank)
     ON r.JobLevel = c.JobLevel
JOIN dbo.OrganizationUnits u ON u.UnitName = c.UnitName
ORDER BY c.Ord;

-- Keep holder counts for the check below (outside the transaction scope of the table)
SELECT p.PositionID, c.Holders INTO #Holders
FROM #Cat c JOIN dbo.Positions p ON p.PositionTitle = c.PositionTitle;

COMMIT TRANSACTION;

-- Check: positions and planned holders per unit (expect 67 positions; holders 1 / 45 / 25 / 20 / 35 / 25)
SELECT u.UnitName,
       COUNT(*)        AS Positions,
       SUM(h.Holders)  AS PlannedHolders
FROM dbo.Positions p
JOIN #Holders h ON h.PositionID = p.PositionID
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = p.OrganizationUnitID
GROUP BY u.OrganizationUnitID, u.UnitName ORDER BY u.OrganizationUnitID;

SELECT COUNT(*) AS TotalPositions, SUM(h.Holders) AS TotalPlannedHolders
FROM dbo.Positions p JOIN #Holders h ON h.PositionID = p.PositionID;

-- Check: planned holders per level (expect 1/5/3/10/17/33/52/30)
SELECT p.JobLevelRank, p.JobLevel, SUM(h.Holders) AS PlannedHolders
FROM dbo.Positions p JOIN #Holders h ON h.PositionID = p.PositionID
GROUP BY p.JobLevelRank, p.JobLevel ORDER BY p.JobLevelRank;

DROP TABLE #Holders;
DROP TABLE #Cat;
GO
