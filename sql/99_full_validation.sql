-- 99_full_validation.sql: final validation of DemoHR. READ-ONLY: nothing in the database is changed
-- (results are collected in temporary tables only).
-- Covers every check in the "Final validation" list of CONTEXT.md, with two changes from PLAN.md:
--   the total is 151 (1 CEO + 150 in the five departments) and employee numbers are EMP-000001 .. EMP-000151.
-- Output: one row per check (name, expected, actual, PASS/FAIL), a summary, and the rows behind every FAIL.
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -f 65001 -W -i sql/99_full_validation.sql
SET NOCOUNT ON;

DECLARE @RefDate    date = '2026-11-16';   -- reference date ("today"); the only place it is written
DECLARE @TotalExp   int  = 151;            -- 1 CEO + 150 in departments
DECLARE @no int;

CREATE TABLE #Res (No int PRIMARY KEY, Section varchar(20), CheckName nvarchar(150), Expected nvarchar(60), Actual nvarchar(60) NULL, Result varchar(4) NULL);
CREATE TABLE #Bad (CheckNo int, RowKey nvarchar(100), Detail nvarchar(300));

-- ============================================================ Employees
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES
(1, 'Employees', N'Total employees (1 CEO + 150 in departments)', CAST(@TotalExp AS nvarchar(60)), CAST((SELECT COUNT(*) FROM dbo.Employees) AS nvarchar(60))),
(2, 'Employees', N'Employees in the five departments', N'150', CAST((SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = e.OrganizationUnitID WHERE u.UnitType = 'Department') AS nvarchar(60))),
(3, 'Employees', N'Employees under the company (the CEO)', N'1', CAST((SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = e.OrganizationUnitID WHERE u.UnitType = 'Company') AS nvarchar(60))),
(4, 'Employees', N'Active employees (employees with an open job-history record)', CAST(@TotalExp AS nvarchar(60)),
    CAST((SELECT COUNT(*) FROM dbo.Employees e WHERE EXISTS (SELECT 1 FROM dbo.EmployeeJobHistory h WHERE h.EmployeeID = e.EmployeeID AND h.EndDate IS NULL)) AS nvarchar(60)));

SET @no = 5;   -- Former employees: no open record would mean the person has left
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, e.FirstName + N' ' + e.LastName + N': no open job-history record' FROM dbo.Employees e
WHERE NOT EXISTS (SELECT 1 FROM dbo.EmployeeJobHistory h WHERE h.EmployeeID = e.EmployeeID AND h.EndDate IS NULL);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Employees', N'Former employees (no open job-history record)', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 6;   -- hire dates inside the reference date
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, N'HireDate ' + CONVERT(nvarchar(10), e.HireDate, 120) FROM dbo.Employees e WHERE e.HireDate > @RefDate;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Employees', N'Hire dates after the reference date', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

-- ============================================================ Employee numbers
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES
(7, 'Employee numbers', N'First employee number', N'EMP-000001', (SELECT MIN(EmployeeNumber) FROM dbo.Employees)),
(8, 'Employee numbers', N'Last employee number',  N'EMP-000151', (SELECT MAX(EmployeeNumber) FROM dbo.Employees)),
(9, 'Employee numbers', N'Distinct employee numbers', CAST(@TotalExp AS nvarchar(60)), CAST((SELECT COUNT(DISTINCT EmployeeNumber) FROM dbo.Employees) AS nvarchar(60)));

SET @no = 10;  -- every number equals EMP- + the 6-digit employee ID, so there are no gaps
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, N'EmployeeID ' + CAST(e.EmployeeID AS nvarchar(10)) FROM dbo.Employees e
WHERE e.EmployeeNumber <> 'EMP-' + RIGHT('000000' + CAST(e.EmployeeID AS varchar(6)), 6) OR e.EmployeeNumber NOT LIKE 'EMP-[0-9][0-9][0-9][0-9][0-9][0-9]';
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Employee numbers', N'Numbers that are not EMP-######, in step with EmployeeID (gaps)', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

-- ============================================================ Departments
INSERT INTO #Res (No, Section, CheckName, Expected, Actual)
SELECT 10 + d.Ord, 'Departments', d.UnitName + N' headcount', CAST(d.Exp AS nvarchar(60)),
       CAST((SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = e.OrganizationUnitID WHERE u.UnitName = d.UnitName AND u.UnitType = 'Department') AS nvarchar(60))
FROM (VALUES (1, N'Technology', 45), (2, N'Finance', 25), (3, N'Human Resources', 20), (4, N'Sales', 35), (5, N'Customer Experience', 25)) d(Ord, UnitName, Exp);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES
(16, 'Departments', N'Workforce plan targets add up to 155 (150 employees + 5 open positions)', N'155', CAST((SELECT SUM(TargetHeadcount) FROM dbo.DepartmentWorkforcePlan) AS nvarchar(60)));

SET @no = 17;  -- no department is above its workforce plan (Technology and Sales are deliberately 3 and 2 below)
INSERT INTO #Bad SELECT @no, u.UnitName, N'target ' + CAST(w.TargetHeadcount AS nvarchar(10)) + N', actual ' + CAST((SELECT COUNT(*) FROM dbo.Employees e WHERE e.OrganizationUnitID = u.OrganizationUnitID) AS nvarchar(10))
FROM dbo.DepartmentWorkforcePlan w JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = w.OrganizationUnitID
WHERE w.TargetHeadcount < (SELECT COUNT(*) FROM dbo.Employees e WHERE e.OrganizationUnitID = u.OrganizationUnitID);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Departments', N'Departments whose headcount is above the workforce plan', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

-- ============================================================ Management
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES
(18, 'Management', N'CEOs', N'1', CAST((SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID WHERE p.JobLevel = 'CEO') AS nvarchar(60)));

SET @no = 19;
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, N'CEO has manager ID ' + CAST(e.ManagerEmployeeID AS nvarchar(10)) FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID WHERE p.JobLevel = 'CEO' AND e.ManagerEmployeeID IS NOT NULL;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Management', N'CEOs that have a manager', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 20;
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, N'no manager' FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID WHERE p.JobLevel <> 'CEO' AND e.ManagerEmployeeID IS NULL;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Management', N'Non-CEO employees without a manager', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 21;
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, N'reports to self' FROM dbo.Employees e WHERE e.ManagerEmployeeID = e.EmployeeID;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Management', N'Self-reporting employees', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 22;  -- walk down from the CEO: everybody must be reached, nobody twice
;WITH tree AS (
    SELECT e.EmployeeID, 0 AS Depth, CAST('/' + CAST(e.EmployeeID AS varchar(10)) + '/' AS varchar(1000)) AS Path FROM dbo.Employees e WHERE e.ManagerEmployeeID IS NULL
    UNION ALL
    SELECT c.EmployeeID, t.Depth + 1, CAST(t.Path + CAST(c.EmployeeID AS varchar(10)) + '/' AS varchar(1000))
    FROM dbo.Employees c JOIN tree t ON c.ManagerEmployeeID = t.EmployeeID
    WHERE t.Depth < 12 AND t.Path NOT LIKE '%/' + CAST(c.EmployeeID AS varchar(10)) + '/%')
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, N'not reachable from the CEO (cycle or orphan)' FROM dbo.Employees e WHERE e.EmployeeID NOT IN (SELECT EmployeeID FROM tree);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Management', N'Employees not reachable from the CEO (circular reporting)', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 23;
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, N'manager ID ' + CAST(e.ManagerEmployeeID AS nvarchar(10)) + N' does not exist' FROM dbo.Employees e
WHERE e.ManagerEmployeeID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Employees m WHERE m.EmployeeID = e.ManagerEmployeeID);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Management', N'Invalid manager IDs', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 24;
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, N'level ' + pe.JobLevel + N' (rank ' + CAST(pe.JobLevelRank AS nvarchar(2)) + N') reports to ' + m.EmployeeNumber + N' level ' + pm.JobLevel + N' (rank ' + CAST(pm.JobLevelRank AS nvarchar(2)) + N')'
FROM dbo.Employees e JOIN dbo.Positions pe ON pe.PositionID = e.PositionID
JOIN dbo.Employees m ON m.EmployeeID = e.ManagerEmployeeID JOIN dbo.Positions pm ON pm.PositionID = m.PositionID
WHERE pm.JobLevelRank >= pe.JobLevelRank;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Management', N'Managers whose level is not strictly higher than the report''s', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

-- ============================================================ Job history
SET @no = 25;
INSERT INTO #Bad SELECT @no, CAST(h.JobHistoryID AS nvarchar(20)), N'EmployeeID ' + CAST(h.EmployeeID AS nvarchar(10)) + N' does not exist' FROM dbo.EmployeeJobHistory h WHERE NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.EmployeeID = h.EmployeeID);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Job history', N'Records with an invalid employee', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 26;
INSERT INTO #Bad SELECT @no, CAST(h.JobHistoryID AS nvarchar(20)), N'PositionID ' + CAST(h.PositionID AS nvarchar(10)) + N' does not exist' FROM dbo.EmployeeJobHistory h WHERE NOT EXISTS (SELECT 1 FROM dbo.Positions p WHERE p.PositionID = h.PositionID);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Job history', N'Records with an invalid position', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 27;
INSERT INTO #Bad SELECT @no, CAST(h.JobHistoryID AS nvarchar(20)), N'OrganizationUnitID ' + CAST(h.OrganizationUnitID AS nvarchar(10)) + N' does not exist' FROM dbo.EmployeeJobHistory h WHERE NOT EXISTS (SELECT 1 FROM dbo.OrganizationUnits u WHERE u.OrganizationUnitID = h.OrganizationUnitID);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Job history', N'Records with an invalid department', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 28;
INSERT INTO #Bad SELECT @no, CAST(h.JobHistoryID AS nvarchar(20)), N'ManagerEmployeeID ' + CAST(h.ManagerEmployeeID AS nvarchar(10)) + N' does not exist' FROM dbo.EmployeeJobHistory h WHERE h.ManagerEmployeeID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Employees m WHERE m.EmployeeID = h.ManagerEmployeeID);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Job history', N'Records with an invalid manager', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 29;  -- no contradictory current state: exactly one open record and it equals the Employees row
INSERT INTO #Bad
SELECT @no, e.EmployeeNumber,
       CASE WHEN (SELECT COUNT(*) FROM dbo.EmployeeJobHistory h WHERE h.EmployeeID = e.EmployeeID AND h.EndDate IS NULL) <> 1 THEN N'open records <> 1'
            ELSE N'open record differs from the Employees row (position, department or manager)' END
FROM dbo.Employees e
WHERE (SELECT COUNT(*) FROM dbo.EmployeeJobHistory h WHERE h.EmployeeID = e.EmployeeID AND h.EndDate IS NULL) <> 1
   OR NOT EXISTS (SELECT 1 FROM dbo.EmployeeJobHistory h WHERE h.EmployeeID = e.EmployeeID AND h.EndDate IS NULL
                  AND h.PositionID = e.PositionID AND h.OrganizationUnitID = e.OrganizationUnitID AND ISNULL(h.ManagerEmployeeID, -1) = ISNULL(e.ManagerEmployeeID, -1));
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Job history', N'Employees whose current state contradicts the open job-history record', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 30;
INSERT INTO #Bad SELECT @no, CAST(h.JobHistoryID AS nvarchar(20)), N'department ' + CAST(h.OrganizationUnitID AS nvarchar(10)) + N' <> position department ' + CAST(p.OrganizationUnitID AS nvarchar(10))
FROM dbo.EmployeeJobHistory h JOIN dbo.Positions p ON p.PositionID = h.PositionID WHERE p.OrganizationUnitID <> h.OrganizationUnitID;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Job history', N'Records whose department differs from the position''s department', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 31;  -- first record on the hire date; each EndDate = next EffectiveDate (no gaps, no overlaps)
;WITH j AS (SELECT h.*, ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate) AS rn, LEAD(EffectiveDate) OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate) AS NextEff FROM dbo.EmployeeJobHistory h)
INSERT INTO #Bad SELECT @no, CAST(j.JobHistoryID AS nvarchar(20)), N'EmployeeID ' + CAST(j.EmployeeID AS nvarchar(10)) + N': ' +
       CASE WHEN j.NextEff IS NOT NULL AND ISNULL(j.EndDate, '9999-12-31') <> j.NextEff THEN N'gap or overlap before the next record' ELSE N'first record is not on the hire date' END
FROM j JOIN dbo.Employees e ON e.EmployeeID = j.EmployeeID
WHERE (j.NextEff IS NOT NULL AND ISNULL(j.EndDate, '9999-12-31') <> j.NextEff) OR (j.rn = 1 AND j.EffectiveDate <> e.HireDate);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Job history', N'Gaps, overlaps, or a first record not on the hire date', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 32;
INSERT INTO #Bad SELECT @no, CAST(h.JobHistoryID AS nvarchar(20)), N'EffectiveDate ' + CONVERT(nvarchar(10), h.EffectiveDate, 120) FROM dbo.EmployeeJobHistory h WHERE h.EffectiveDate > @RefDate;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Job history', N'Records starting after the reference date', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

-- ============================================================ Compensation
SET @no = 33;
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, N'no current compensation record' FROM dbo.Employees e WHERE NOT EXISTS (SELECT 1 FROM dbo.EmployeeCompensationHistory c WHERE c.EmployeeID = e.EmployeeID AND c.EndDate IS NULL);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Compensation', N'Employees without current compensation (open record, EndDate NULL)', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 34;
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, CAST(COUNT(*) AS nvarchar(10)) + N' open records' FROM dbo.Employees e JOIN dbo.EmployeeCompensationHistory c ON c.EmployeeID = e.EmployeeID AND c.EndDate IS NULL GROUP BY e.EmployeeNumber HAVING COUNT(*) > 1;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Compensation', N'Employees with more than one current record', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 35;
INSERT INTO #Bad SELECT @no, CAST(a.CompensationHistoryID AS nvarchar(20)) + N'/' + CAST(b.CompensationHistoryID AS nvarchar(20)), N'EmployeeID ' + CAST(a.EmployeeID AS nvarchar(10)) + N': periods overlap'
FROM dbo.EmployeeCompensationHistory a JOIN dbo.EmployeeCompensationHistory b ON b.EmployeeID = a.EmployeeID AND b.CompensationHistoryID > a.CompensationHistoryID
WHERE a.EffectiveDate < ISNULL(b.EndDate, '9999-12-31') AND b.EffectiveDate < ISNULL(a.EndDate, '9999-12-31');
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Compensation', N'Overlapping compensation periods', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 36;  -- gaps, first record on the hire date, salary dates inside the reference date
;WITH j AS (SELECT c.*, ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate) AS rn, LEAD(EffectiveDate) OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate) AS NextEff FROM dbo.EmployeeCompensationHistory c)
INSERT INTO #Bad SELECT @no, CAST(j.CompensationHistoryID AS nvarchar(20)), N'EmployeeID ' + CAST(j.EmployeeID AS nvarchar(10)) + N': ' +
       CASE WHEN j.NextEff IS NOT NULL AND ISNULL(j.EndDate, '9999-12-31') <> j.NextEff THEN N'gap before the next record'
            WHEN j.EffectiveDate > @RefDate THEN N'starts after the reference date' ELSE N'first record is not on the hire date' END
FROM j JOIN dbo.Employees e ON e.EmployeeID = j.EmployeeID
WHERE (j.NextEff IS NOT NULL AND ISNULL(j.EndDate, '9999-12-31') <> j.NextEff) OR (j.rn = 1 AND j.EffectiveDate <> e.HireDate) OR j.EffectiveDate > @RefDate;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Compensation', N'Gaps, a first record not on the hire date, or records after the reference date', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

-- ============================================================ Performance
SET @no = 37;
INSERT INTO #Bad SELECT @no, CAST(r.PerformanceReviewID AS nvarchar(20)), N'EmployeeID ' + CAST(r.EmployeeID AS nvarchar(10)) + N' does not exist' FROM dbo.PerformanceReviews r WHERE NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.EmployeeID = r.EmployeeID);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Performance', N'Reviews with an invalid employee', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 38;
INSERT INTO #Bad SELECT @no, CAST(r.PerformanceReviewID AS nvarchar(20)), N'ReviewerEmployeeID ' + CAST(r.ReviewerEmployeeID AS nvarchar(10)) + CASE WHEN r.ReviewerEmployeeID = r.EmployeeID THEN N' is the employee' ELSE N' does not exist' END
FROM dbo.PerformanceReviews r WHERE r.ReviewerEmployeeID = r.EmployeeID OR NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.EmployeeID = r.ReviewerEmployeeID);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Performance', N'Reviews with an invalid reviewer', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 39;
INSERT INTO #Bad SELECT @no, CAST(r.PerformanceReviewID AS nvarchar(20)), N'rating ' + CAST(r.OverallRating AS nvarchar(10)) FROM dbo.PerformanceReviews r WHERE r.OverallRating < 1.0 OR r.OverallRating > 5.0;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Performance', N'Ratings outside 1.0 to 5.0', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 40;  -- period start < end < review date, review after hire, not after the reference date, none for the current year
INSERT INTO #Bad SELECT @no, CAST(r.PerformanceReviewID AS nvarchar(20)),
       N'period ' + CONVERT(nvarchar(10), r.ReviewPeriodStart, 120) + N' to ' + CONVERT(nvarchar(10), r.ReviewPeriodEnd, 120) + N', review date ' + CONVERT(nvarchar(10), r.ReviewDate, 120)
FROM dbo.PerformanceReviews r JOIN dbo.Employees e ON e.EmployeeID = r.EmployeeID
WHERE NOT (r.ReviewPeriodStart < r.ReviewPeriodEnd AND r.ReviewPeriodEnd < r.ReviewDate) OR r.ReviewDate <= e.HireDate OR r.ReviewDate > @RefDate OR YEAR(r.ReviewPeriodEnd) >= YEAR(@RefDate);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Performance', N'Reviews with invalid dates (order, before hire, after the reference date, current year)', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

-- ============================================================ Leave
SET @no = 41;
INSERT INTO #Bad SELECT @no, CAST(l.LeaveID AS nvarchar(20)), N'EmployeeID ' + CAST(l.EmployeeID AS nvarchar(10)) + N' does not exist' FROM dbo.EmployeeLeaves l WHERE NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.EmployeeID = l.EmployeeID);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Leave', N'Leaves with an invalid employee', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 42;
INSERT INTO #Bad SELECT @no, CAST(l.LeaveID AS nvarchar(20)), N'LeaveTypeID ' + CAST(l.LeaveTypeID AS nvarchar(10)) + N' does not exist' FROM dbo.EmployeeLeaves l WHERE NOT EXISTS (SELECT 1 FROM dbo.LeaveTypes t WHERE t.LeaveTypeID = l.LeaveTypeID);
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Leave', N'Leaves with an invalid leave type', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 43;
INSERT INTO #Bad SELECT @no, CAST(l.LeaveID AS nvarchar(20)), N'start ' + CONVERT(nvarchar(10), l.StartDate, 120) + N' after end ' + CONVERT(nvarchar(10), l.EndDate, 120) FROM dbo.EmployeeLeaves l WHERE l.StartDate > l.EndDate;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Leave', N'Leaves where StartDate is after EndDate', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 44;  -- Pending: no approver. Approved / Rejected: an approver who exists, is not the employee, and was already employed on the start date
INSERT INTO #Bad SELECT @no, CAST(l.LeaveID AS nvarchar(20)),
       N'Status ' + l.Status + CASE WHEN l.Status = 'Pending' THEN N' but has an approver' WHEN l.ApprovedByEmployeeID IS NULL THEN N' without an approver'
                                    WHEN l.ApprovedByEmployeeID = l.EmployeeID THEN N' approved by the employee' ELSE N' with an approver who does not exist or was not employed on the start date' END
FROM dbo.EmployeeLeaves l
WHERE (l.Status = 'Pending' AND l.ApprovedByEmployeeID IS NOT NULL)
   OR (l.Status <> 'Pending' AND (l.ApprovedByEmployeeID IS NULL OR l.ApprovedByEmployeeID = l.EmployeeID
        OR NOT EXISTS (SELECT 1 FROM dbo.Employees a WHERE a.EmployeeID = l.ApprovedByEmployeeID AND a.HireDate <= l.StartDate)));
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Leave', N'Leaves with an invalid approval relationship', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

-- ============================================================ Pictures (profile images are created after the data is final)
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES
(45, 'Pictures', N'Employees', CAST(@TotalExp AS nvarchar(60)), CAST((SELECT COUNT(*) FROM dbo.Employees) AS nvarchar(60))),
(46, 'Pictures', N'Employees with a picture filename', CAST(@TotalExp AS nvarchar(60)), CAST((SELECT COUNT(ProfileImageFileName) FROM dbo.Employees) AS nvarchar(60)));

SET @no = 47;
INSERT INTO #Bad SELECT @no, ProfileImageFileName, CAST(COUNT(*) AS nvarchar(10)) + N' employees share this filename' FROM dbo.Employees WHERE ProfileImageFileName IS NOT NULL GROUP BY ProfileImageFileName HAVING COUNT(*) > 1;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Pictures', N'Duplicate picture filenames', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

SET @no = 48;  -- every filename is EmployeeNumber + .jpg
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, CASE WHEN e.ProfileImageFileName IS NULL THEN N'no picture filename' ELSE N'filename ' + e.ProfileImageFileName + N' is not ' + e.EmployeeNumber + N'.jpg' END
FROM dbo.Employees e WHERE e.ProfileImageFileName IS NULL OR e.ProfileImageFileName <> e.EmployeeNumber + '.jpg';
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Pictures', N'Employees whose filename is missing or is not EmployeeNumber.jpg', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

-- The database holds only filenames, so it cannot see the gender of a picture: that review is manual.
-- This row only counts the pictures that exist and can be reviewed (all of them must be reviewed against Employees.Gender).
SET @no = 49;
INSERT INTO #Bad SELECT @no, e.EmployeeNumber, N'no picture to review (gender ' + e.Gender + N')' FROM dbo.Employees e WHERE e.ProfileImageFileName IS NULL;
INSERT INTO #Res (No, Section, CheckName, Expected, Actual) VALUES (@no, 'Pictures', N'Employees without a picture to review against their gender (image review is manual)', N'0', CAST((SELECT COUNT(*) FROM #Bad WHERE CheckNo = @no) AS nvarchar(60)));

-- ============================================================ results
UPDATE #Res SET Result = CASE WHEN Actual = Expected THEN 'PASS' ELSE 'FAIL' END;

PRINT '=== Full validation (reference date ' + CONVERT(varchar(10), @RefDate, 120) + ')';
SELECT No, Section, CheckName AS [Check], Expected, Actual, Result FROM #Res ORDER BY No;

SELECT SUM(CASE WHEN Result = 'PASS' THEN 1 ELSE 0 END) AS Passed, SUM(CASE WHEN Result = 'FAIL' THEN 1 ELSE 0 END) AS Failed, COUNT(*) AS Checks FROM #Res;

PRINT '=== Rows behind every FAIL (first 25 per check; Total = all offending rows)';
SELECT r.No, r.CheckName AS [Check], b.RowKey, b.Detail, t.Total
FROM #Res r
JOIN (SELECT CheckNo, RowKey, Detail, ROW_NUMBER() OVER (PARTITION BY CheckNo ORDER BY RowKey) AS rn FROM #Bad) b ON b.CheckNo = r.No AND b.rn <= 25
JOIN (SELECT CheckNo, COUNT(*) AS Total FROM #Bad GROUP BY CheckNo) t ON t.CheckNo = r.No
WHERE r.Result = 'FAIL' ORDER BY r.No, b.RowKey;

PRINT '=== FAIL checks that have no offending rows (count or value checks)';
SELECT No, CheckName AS [Check], Expected, Actual FROM #Res WHERE Result = 'FAIL' AND NOT EXISTS (SELECT 1 FROM #Bad b WHERE b.CheckNo = #Res.No) ORDER BY No;

DROP TABLE #Res, #Bad;
GO
