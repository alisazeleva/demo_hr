-- 02_seed_organization.sql: Acme Corporation (company) and its 5 departments.
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -i sql/02_seed_organization.sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
BEGIN TRANSACTION;

-- Clear only this table (departments first because of the self-reference)
DELETE FROM dbo.OrganizationUnits WHERE ParentUnitID IS NOT NULL;
DELETE FROM dbo.OrganizationUnits;
-- Restart IDs at 1 (a never-used identity needs seed 1, a used one needs 0)
DECLARE @seed int = CASE WHEN EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.OrganizationUnits') AND last_value IS NULL) THEN 1 ELSE 0 END;
DBCC CHECKIDENT ('dbo.OrganizationUnits', RESEED, @seed) WITH NO_INFOMSGS;

INSERT INTO dbo.OrganizationUnits (UnitName, UnitType, ParentUnitID)
VALUES (N'Acme Corporation', 'Company', NULL);

DECLARE @CompanyID int = (SELECT OrganizationUnitID FROM dbo.OrganizationUnits WHERE UnitType = 'Company');

INSERT INTO dbo.OrganizationUnits (UnitName, UnitType, ParentUnitID)
VALUES (N'Technology',         'Department', @CompanyID),
       (N'Finance',            'Department', @CompanyID),
       (N'Human Resources',    'Department', @CompanyID),
       (N'Sales',              'Department', @CompanyID),
       (N'Customer Experience','Department', @CompanyID);

COMMIT TRANSACTION;
GO

-- Check: 1 company, 5 departments, every department under the company
SELECT SUM(CASE WHEN u.UnitType = 'Company' THEN 1 ELSE 0 END)    AS Companies,
       SUM(CASE WHEN u.UnitType = 'Department' THEN 1 ELSE 0 END) AS Departments,
       SUM(CASE WHEN u.UnitType = 'Department' AND u.ParentUnitID = c.OrganizationUnitID THEN 1 ELSE 0 END) AS DepartmentsUnderCompany
FROM dbo.OrganizationUnits u
CROSS JOIN (SELECT OrganizationUnitID FROM dbo.OrganizationUnits WHERE UnitType = 'Company') c;
SELECT OrganizationUnitID, UnitName, UnitType, ParentUnitID FROM dbo.OrganizationUnits ORDER BY OrganizationUnitID;
GO
