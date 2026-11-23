-- 01_start.sql: open the transaction and record the run (step 2 of sql/15_generate_2027_2030.sql)
-- Everything from here to the COMMIT in 90_finish.sql is one transaction. XACT_ABORT is ON and sqlcmd runs with ":on error exit",
-- so any error ends the connection and SQL Server rolls the whole run back.
-- Tables of script 13 that this step fills: ReferenceDateLog, DepartmentWorkforcePlanHistory, LeaveRequestInfo.
-- Rule for the data of scripts 06 to 11: those rows stay as they are; the only change is the EndDate of an open job-history or
-- pay row when a newer row starts. Signatures of the old rows are taken here and compared in 90_finish.sql.
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID(N'tempdb..#Counts') IS NOT NULL DROP TABLE #Counts;
CREATE TABLE #Counts (TableName sysname NOT NULL, RowsBefore int NOT NULL, RowsAfter int NULL);
INSERT #Counts (TableName, RowsBefore)
SELECT N'Employees', COUNT(*) FROM dbo.Employees
UNION ALL SELECT N'EmployeeJobHistory', COUNT(*) FROM dbo.EmployeeJobHistory
UNION ALL SELECT N'EmployeeCompensationHistory', COUNT(*) FROM dbo.EmployeeCompensationHistory
UNION ALL SELECT N'PerformanceReviews', COUNT(*) FROM dbo.PerformanceReviews
UNION ALL SELECT N'EmployeeLeaves', COUNT(*) FROM dbo.EmployeeLeaves;

-- signatures of the old rows (for the job and pay rows the EndDate is left out: an open row may be closed; closed rows are checked on their own)
IF OBJECT_ID(N'tempdb..#Sig') IS NOT NULL DROP TABLE #Sig;
CREATE TABLE #Sig (Name varchar(40) PRIMARY KEY, Sig int NULL, MaxID int NULL);
INSERT #Sig (Name, Sig, MaxID)
SELECT 'Employees', CHECKSUM_AGG(CHECKSUM(EmployeeID, EmployeeNumber, FirstName, LastName, Gender, DateOfBirth, Nationality, NativeLanguage, HireDate, EmailAddress, PositionID, OrganizationUnitID, ManagerEmployeeID, ProfileImageFileName)), MAX(EmployeeID) FROM dbo.Employees
UNION ALL SELECT 'JobHistory', CHECKSUM_AGG(CHECKSUM(JobHistoryID, EmployeeID, EffectiveDate, PositionID, OrganizationUnitID, ManagerEmployeeID, ChangeType, Reason)), MAX(JobHistoryID) FROM dbo.EmployeeJobHistory
UNION ALL SELECT 'JobHistoryClosed', CHECKSUM_AGG(CHECKSUM(JobHistoryID, EndDate)), MAX(JobHistoryID) FROM dbo.EmployeeJobHistory WHERE EndDate IS NOT NULL
UNION ALL SELECT 'Compensation', CHECKSUM_AGG(CHECKSUM(CompensationHistoryID, EmployeeID, EffectiveDate, BaseSalary, Currency, PayFrequency, ChangeReason)), MAX(CompensationHistoryID) FROM dbo.EmployeeCompensationHistory
UNION ALL SELECT 'CompensationClosed', CHECKSUM_AGG(CHECKSUM(CompensationHistoryID, EndDate)), MAX(CompensationHistoryID) FROM dbo.EmployeeCompensationHistory WHERE EndDate IS NOT NULL
UNION ALL SELECT 'Reviews', CHECKSUM_AGG(CHECKSUM(PerformanceReviewID, EmployeeID, ReviewerEmployeeID, ReviewDate, ReviewPeriodStart, ReviewPeriodEnd, OverallRating, PerformanceLevel, Comments)), MAX(PerformanceReviewID) FROM dbo.PerformanceReviews
UNION ALL SELECT 'Leaves', CHECKSUM_AGG(CHECKSUM(LeaveID, EmployeeID, LeaveTypeID, StartDate, EndDate, Status, ApprovedByEmployeeID, Notes)), MAX(LeaveID) FROM dbo.EmployeeLeaves
UNION ALL SELECT 'WorkforcePlan', CHECKSUM_AGG(CHECKSUM(WorkforcePlanID, OrganizationUnitID, TargetHeadcount)), MAX(WorkforcePlanID) FROM dbo.DepartmentWorkforcePlan;

BEGIN TRANSACTION;


INSERT dbo.ReferenceDateLog (OldReferenceDate, NewReferenceDate, Note) SELECT OldDate, NewDate, N'Data 2026-11-17 to 2030-12-31 (script 15)' FROM #Run;
