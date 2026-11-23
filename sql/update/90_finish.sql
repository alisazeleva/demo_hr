-- 90_finish.sql: check, report and commit (last step of sql/extend_data.sql)
-- Any failed check THROWs; with ":on error exit" the connection closes and the open transaction is rolled back.
SET NOCOUNT ON;

-- the log must show the new end of the data
IF (SELECT MAX(NewReferenceDate) FROM dbo.ReferenceDateLog) <> (SELECT NewDate FROM #Run)
    THROW 50010, 'The run log does not show the new end date.', 1;

-- old rows must be exactly as they were (signatures from 02_log_run.sql); the EndDate of an old open row may now be filled,
-- an old closed row keeps its EndDate (it is not later than the old end of data; rows closed in this run end after it)
DECLARE @Old date = (SELECT OldDate FROM #Run);
DECLARE @bad varchar(400) = '';
SELECT @bad = @bad + Name + ' ' FROM #Sig s WHERE ISNULL(Sig, 0) <> ISNULL(CASE Name
    WHEN 'Employees'          THEN (SELECT CHECKSUM_AGG(CHECKSUM(EmployeeID, EmployeeNumber, FirstName, LastName, Gender, DateOfBirth, Nationality, NativeLanguage, HireDate, EmailAddress, PositionID, OrganizationUnitID, ManagerEmployeeID, ProfileImageFileName)) FROM dbo.Employees WHERE EmployeeID <= s.MaxID)
    WHEN 'JobHistory'         THEN (SELECT CHECKSUM_AGG(CHECKSUM(JobHistoryID, EmployeeID, EffectiveDate, PositionID, OrganizationUnitID, ManagerEmployeeID, ChangeType, Reason)) FROM dbo.EmployeeJobHistory WHERE JobHistoryID <= s.MaxID)
    WHEN 'JobHistoryClosed'   THEN (SELECT CHECKSUM_AGG(CHECKSUM(JobHistoryID, EndDate)) FROM dbo.EmployeeJobHistory WHERE JobHistoryID <= s.MaxID AND EndDate IS NOT NULL AND EndDate <= @Old)
    WHEN 'Compensation'       THEN (SELECT CHECKSUM_AGG(CHECKSUM(CompensationHistoryID, EmployeeID, EffectiveDate, BaseSalary, Currency, PayFrequency, ChangeReason)) FROM dbo.EmployeeCompensationHistory WHERE CompensationHistoryID <= s.MaxID)
    WHEN 'CompensationClosed' THEN (SELECT CHECKSUM_AGG(CHECKSUM(CompensationHistoryID, EndDate)) FROM dbo.EmployeeCompensationHistory WHERE CompensationHistoryID <= s.MaxID AND EndDate IS NOT NULL AND EndDate <= @Old)
    WHEN 'Reviews'            THEN (SELECT CHECKSUM_AGG(CHECKSUM(PerformanceReviewID, EmployeeID, ReviewerEmployeeID, ReviewDate, ReviewPeriodStart, ReviewPeriodEnd, OverallRating, PerformanceLevel, Comments)) FROM dbo.PerformanceReviews WHERE PerformanceReviewID <= s.MaxID)
    WHEN 'Leaves'             THEN (SELECT CHECKSUM_AGG(CHECKSUM(LeaveID, EmployeeID, LeaveTypeID, StartDate, EndDate, Status, ApprovedByEmployeeID, Notes)) FROM dbo.EmployeeLeaves WHERE LeaveID <= s.MaxID)
    WHEN 'WorkforcePlan'      THEN (SELECT CHECKSUM_AGG(CHECKSUM(WorkforcePlanID, OrganizationUnitID, TargetHeadcount)) FROM dbo.DepartmentWorkforcePlan WHERE WorkforcePlanID <= s.MaxID) END, 0);
IF @bad <> ''
BEGIN
    DECLARE @Msg nvarchar(500) = N'An old row was changed in: ' + @bad;
    THROW 50011, @Msg, 1;
END;

-- general rules: one open job row and one open pay row per employee, no gaps, no overlaps
IF EXISTS (SELECT 1 FROM dbo.Employees e WHERE (SELECT COUNT(*) FROM dbo.EmployeeJobHistory j WHERE j.EmployeeID = e.EmployeeID AND j.EndDate IS NULL) <> 1
                                                 OR (SELECT COUNT(*) FROM dbo.EmployeeCompensationHistory c WHERE c.EmployeeID = e.EmployeeID AND c.EndDate IS NULL) <> 1)
    THROW 50012, 'An employee has no or more than one open job or pay row.', 1;
;WITH j AS (SELECT EndDate, LEAD(EffectiveDate) OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate) AS NextEff FROM dbo.EmployeeJobHistory),
      c AS (SELECT EndDate, LEAD(EffectiveDate) OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate) AS NextEff FROM dbo.EmployeeCompensationHistory)
SELECT 1 AS Bad INTO #Gap FROM j WHERE NextEff IS NOT NULL AND ISNULL(EndDate, '9999-12-31') <> NextEff
UNION ALL SELECT 1 FROM c WHERE NextEff IS NOT NULL AND ISNULL(EndDate, '9999-12-31') <> NextEff;
IF EXISTS (SELECT 1 FROM #Gap) THROW 50013, 'A job or pay history has a gap or an overlap.', 1;
DROP TABLE #Gap;

UPDATE c SET RowsAfter = CASE c.TableName
        WHEN N'Employees'                   THEN (SELECT COUNT(*) FROM dbo.Employees)
        WHEN N'EmployeeJobHistory'          THEN (SELECT COUNT(*) FROM dbo.EmployeeJobHistory)
        WHEN N'EmployeeCompensationHistory' THEN (SELECT COUNT(*) FROM dbo.EmployeeCompensationHistory)
        WHEN N'PerformanceReviews'          THEN (SELECT COUNT(*) FROM dbo.PerformanceReviews)
        WHEN N'EmployeeLeaves'              THEN (SELECT COUNT(*) FROM dbo.EmployeeLeaves) END
FROM #Counts c;

COMMIT TRANSACTION;

SELECT r.OldDate AS OldEndOfData, r.NewDate AS NewEndOfData FROM #Run r;
SELECT TableName, RowsBefore, RowsAfter, RowsAfter - RowsBefore AS Added FROM #Counts ORDER BY TableName;
