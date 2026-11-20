-- 12_assign_profile_pictures.sql: sets Employees.ProfileImageFileName to EmployeeNumber + '.jpg' (EMP-000001.jpg ...).
-- The database stores only the file names; the pictures are made outside it (images/ folder) and Power BI loads the files.
-- A file name can exist before its picture does: the report simply shows no picture for an employee without a file.
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -f 65001 -i sql/12_assign_profile_pictures.sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRANSACTION;

UPDATE dbo.Employees
SET ProfileImageFileName = EmployeeNumber + '.jpg'
WHERE ProfileImageFileName IS NULL OR ProfileImageFileName <> EmployeeNumber + '.jpg';

DECLARE @Total int = (SELECT COUNT(*) FROM dbo.Employees);
DECLARE @Named int = (SELECT COUNT(*) FROM dbo.Employees WHERE ProfileImageFileName = EmployeeNumber + '.jpg');
IF @Named <> @Total
BEGIN
    RAISERROR('Profile picture file names were not assigned to every employee.', 16, 1);
    ROLLBACK TRANSACTION;
    RETURN;
END;

COMMIT TRANSACTION;
PRINT 'Profile picture file names assigned: ' + CAST(@Named AS varchar(10)) + ' of ' + CAST(@Total AS varchar(10)) + '.';
