-- 04_run_calendar.sql: add the new records, one date at a time in date order (step 5 of sql/15_generate_2027_2030.sql)
-- For every date of #Cal: first the quarter-start changes (04b_quarter.sql: promotions, transfers, annual increase, market adjustment),
-- then the hire if the date is a hire slot (04a_hire.sql). The dates are handled in order, so every run gives identical data.
-- Runs inside the transaction opened by 01_start.sql.
-- State used while running: the OPEN rows of EmployeeJobHistory (position, department, manager) and EmployeeCompensationHistory (salary).
-- The Employees rows of people who were there before are never updated (they stay as of the first load); a new hire's Employees row
-- holds the position, department and manager at hire.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Seed varchar(30) = 'demohr-update-v1';
DECLARE @CalSeq int = 1, @CalMax int = (SELECT COUNT(*) FROM #Cal);
DECLARE @Date date, @IsHire bit, @IsQuarter bit;

WHILE @CalSeq <= @CalMax
BEGIN
    SELECT @Date = D, @IsHire = IsHire, @IsQuarter = IsQuarter FROM #Cal WHERE Seq = @CalSeq;

    IF @IsQuarter = 1
    BEGIN
:r sql/15_generate_2027_2030/04b_quarter.sql
    END;

    IF @IsHire = 1
    BEGIN
:r sql/15_generate_2027_2030/04a_hire.sql
    END;

    SET @CalSeq += 1;
END;

-- ================================================================ report
SELECT COUNT(*) AS NewHires FROM #Hired;
SELECT e.EmployeeNumber, e.FirstName + N' ' + e.LastName AS FullName, e.Gender, e.Nationality, e.DateOfBirth, e.HireDate, p.PositionTitle,
       u.UnitName AS Department, m.FirstName + N' ' + m.LastName AS Manager, c.BaseSalary, e.EmailAddress, e.ProfileImageFileName
FROM #Hired h
JOIN dbo.Employees e ON e.EmployeeID = h.EmployeeID
JOIN dbo.Positions p ON p.PositionID = e.PositionID
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = e.OrganizationUnitID
JOIN dbo.Employees m ON m.EmployeeID = e.ManagerEmployeeID
JOIN dbo.EmployeeCompensationHistory c ON c.EmployeeID = e.EmployeeID AND c.EffectiveDate = e.HireDate
ORDER BY e.EmployeeID;

SELECT j.ChangeType AS JobChange, COUNT(*) AS Changes FROM dbo.EmployeeJobHistory j JOIN #Run r ON j.EffectiveDate > r.OldDate AND j.EffectiveDate <= r.NewDate
WHERE j.ChangeType <> 'Initial Assignment' GROUP BY j.ChangeType ORDER BY j.ChangeType;
SELECT k.ChangeReason AS PayChange, COUNT(*) AS Changes FROM dbo.EmployeeCompensationHistory k JOIN #Run r ON k.EffectiveDate > r.OldDate AND k.EffectiveDate <= r.NewDate
WHERE k.ChangeReason <> 'Initial Salary' GROUP BY k.ChangeReason ORDER BY k.ChangeReason;

DROP TABLE #Cal, #Slot, #Quota, #StaffMap, #Band, #DF, #Acc, #Hired;
