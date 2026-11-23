-- 04a_hire.sql: one new employee on @Date (included inside the loop of 04_run_calendar.sql, so it has no GO)
-- Who: same rules as 06_generate_employees.sql. The department is one below its workforce target (Technology 48, Sales 37 at the start),
--   weighted by the gap, else chosen in proportion to its size; the level is Junior 45%, Professional 40%, Senior 15% (new people do not
--   join as managers); the position is one of the department's positions at that level; the manager is the manager of the same job
--   family with the smallest team (teams stay balanced); the gender is the one that is less common in that department and level;
--   the nationality follows the company quotas; names come from DummyNames (full name and e-mail never repeat an existing one).
--   Age at hire: Junior 22-30, Professional 25-38, Senior 30-46.
-- Records: Employees row (number from the next ID, picture file <number>.jpg, e-mail firstname.lastname@acmecorp.example),
--   one open EmployeeJobHistory row (Initial Assignment) and one open EmployeeCompensationHistory row (Initial Salary: lower half of the
--   level band times the department factor and a personal factor, a multiple of 100 EUR, as in 09_generate_compensation.sql).
--   A department whose headcount passes its target gets a new target row (DepartmentWorkforcePlanHistory) equal to the headcount.
-- Headcounts, teams and targets are read from the open job-history rows and the latest history row, so earlier changes of the same run count.
-- Deterministic: every random value is a hash of (seed, hire date, label).
DECLARE @Key varchar(8) = CONVERT(varchar(8), @Date, 112);

-- random numbers 0 <= R < 1 for this hire
CREATE TABLE #H (Label varchar(10) PRIMARY KEY, R float NOT NULL);
INSERT #H
SELECT l.Label, (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @Key, '|', l.Label)), 1, 4) AS int) & 2147483647) / 2147483648.0
FROM (VALUES ('dept'),('level'),('gender'),('nat'),('swe'),('age'),('days'),('sal'),('pf')) l(Label);

-- department: below target first (weighted by the gap), else by size
DECLARE @Unit int;
;WITH u AS (
    SELECT w.OrganizationUnitID AS UnitID,
           (SELECT TOP 1 h.TargetHeadcount FROM dbo.DepartmentWorkforcePlanHistory h WHERE h.OrganizationUnitID = w.OrganizationUnitID ORDER BY h.EffectiveDate DESC) AS Tgt,
           (SELECT COUNT(*) FROM dbo.EmployeeJobHistory j WHERE j.OrganizationUnitID = w.OrganizationUnitID AND j.EndDate IS NULL) AS Hc
    FROM dbo.DepartmentWorkforcePlan w
), x AS (
    SELECT UnitID, Wt = CASE WHEN EXISTS (SELECT 1 FROM u WHERE Tgt > Hc) THEN CASE WHEN Tgt > Hc THEN Tgt - Hc ELSE 0 END ELSE Hc END FROM u
), c AS (
    SELECT UnitID, Wt, Cum = SUM(Wt) OVER (ORDER BY UnitID ROWS UNBOUNDED PRECEDING), Total = SUM(Wt) OVER ()
    FROM x
)
SELECT @Unit = UnitID FROM c, #H WHERE #H.Label = 'dept' AND Wt > 0 AND #H.R * c.Total >= c.Cum - c.Wt AND #H.R * c.Total < c.Cum;

-- level and position
DECLARE @Rank int = (SELECT CASE WHEN R < 0.45 THEN 8 WHEN R < 0.85 THEN 7 ELSE 6 END FROM #H WHERE Label = 'level');
DECLARE @Pos int, @Family nvarchar(50), @PosTitle nvarchar(100), @Level varchar(20);
SELECT TOP 1 @Pos = p.PositionID, @Family = p.JobFamily, @PosTitle = p.PositionTitle, @Level = p.JobLevel
FROM dbo.Positions p WHERE p.OrganizationUnitID = @Unit AND p.JobLevelRank = @Rank
ORDER BY HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @Key, '|pos|', p.PositionID));

-- manager: the manager of the same family with the fewest direct reports
DECLARE @Mgr int;
SELECT TOP 1 @Mgr = jm.EmployeeID
FROM #StaffMap sm
JOIN dbo.Positions mp ON mp.PositionTitle = sm.MgrTitle AND mp.OrganizationUnitID = @Unit
JOIN dbo.EmployeeJobHistory jm ON jm.PositionID = mp.PositionID AND jm.EndDate IS NULL
WHERE sm.Family = @Family
ORDER BY (SELECT COUNT(*) FROM dbo.EmployeeJobHistory r WHERE r.ManagerEmployeeID = jm.EmployeeID AND r.EndDate IS NULL),
         HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @Key, '|mgr|', jm.EmployeeID));

-- gender: the one that is less common in this department and level
DECLARE @Female int, @Male int, @Gender varchar(10);
SELECT @Female = SUM(CASE WHEN e.Gender = 'Female' THEN 1 ELSE 0 END), @Male = SUM(CASE WHEN e.Gender = 'Male' THEN 1 ELSE 0 END)
FROM dbo.EmployeeJobHistory j JOIN dbo.Employees e ON e.EmployeeID = j.EmployeeID JOIN dbo.Positions p ON p.PositionID = j.PositionID
WHERE j.EndDate IS NULL AND j.OrganizationUnitID = @Unit AND p.JobLevelRank = @Rank;
SET @Gender = CASE WHEN @Female < @Male THEN 'Female' WHEN @Male < @Female THEN 'Male'
                   WHEN (SELECT R FROM #H WHERE Label = 'gender') < 0.5 THEN 'Female' ELSE 'Male' END;

-- nationality by company quota, native language (5% of Finnish nationals speak Swedish)
DECLARE @Nat nvarchar(60), @Lang nvarchar(60);
;WITH q AS (SELECT Nationality, Cum = SUM(Cnt) OVER (ORDER BY Ord ROWS UNBOUNDED PRECEDING), Cnt, Tot = SUM(Cnt) OVER () FROM #Quota)
SELECT @Nat = q.Nationality FROM q, #H WHERE #H.Label = 'nat' AND #H.R * q.Tot >= q.Cum - q.Cnt AND #H.R * q.Tot < q.Cum;
IF @Nat = N'Finnish' AND (SELECT R FROM #H WHERE Label = 'swe') < 0.05 SET @Lang = N'Swedish'
ELSE SELECT TOP 1 @Lang = NativeLanguage FROM dbo.DummyNames WHERE Nationality = @Nat AND NOT (Nationality = N'Finnish' AND NativeLanguage = N'Swedish');

-- names (the combination must be new)
DECLARE @First nvarchar(60), @Last nvarchar(60);
SELECT TOP 1 @First = d.NameValue FROM dbo.DummyNames d
WHERE d.NameType = 'First' AND d.Nationality = @Nat AND d.NativeLanguage = @Lang AND d.Gender = @Gender
ORDER BY HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @Key, '|fn|', d.DummyNameID));
SELECT TOP 1 @Last = d.NameValue FROM dbo.DummyNames d
WHERE d.NameType = 'Last' AND d.Nationality = @Nat AND d.NativeLanguage = @Lang
  AND NOT EXISTS (SELECT 1 FROM dbo.Employees e WHERE e.FirstName = @First AND e.LastName = d.NameValue)
ORDER BY HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @Key, '|ln|', d.DummyNameID));

-- e-mail: firstname.lastname, accents removed, a number only if the address exists
DECLARE @Email nvarchar(150) = LOWER(@First) + N'.' + LOWER(@Last);
DECLARE @ch nvarchar(1), @rep varchar(1);
DECLARE accs CURSOR LOCAL FAST_FORWARD FOR SELECT Ch, Rep FROM #Acc ORDER BY Ch;
OPEN accs; FETCH NEXT FROM accs INTO @ch, @rep;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Email = REPLACE(@Email COLLATE Latin1_General_BIN2, @ch, @rep);
    FETCH NEXT FROM accs INTO @ch, @rep;
END
CLOSE accs; DEALLOCATE accs;
DECLARE @EmailBase nvarchar(150) = @Email, @n int = 1;
WHILE EXISTS (SELECT 1 FROM dbo.Employees WHERE EmailAddress = @Email + N'@acmecorp.example')
BEGIN SET @n += 1; SET @Email = @EmailBase + N'.' + CAST(@n AS nvarchar(5)); END;
SET @Email = @Email + N'@acmecorp.example';

-- date of birth: age at hire by level
DECLARE @Age int = (SELECT CASE @Rank WHEN 8 THEN 22 + CAST(FLOOR(R * 9) AS int) WHEN 7 THEN 25 + CAST(FLOOR(R * 14) AS int)
                                      ELSE 30 + CAST(FLOOR(R * 17) AS int) END FROM #H WHERE Label = 'age');
DECLARE @Dob date = DATEADD(DAY, -CAST(FLOOR((SELECT R FROM #H WHERE Label = 'days') * 365) AS int), DATEADD(YEAR, -@Age, @Date));

-- starting salary: lower half of the level band x department factor x personal factor, a multiple of 100
DECLARE @Salary decimal(10,2);
SELECT @Salary = CASE WHEN s.Rounded < s.LowB THEN s.LowB WHEN s.Rounded > s.HighB THEN s.HighB ELSE s.Rounded END
FROM #Band b
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = @Unit
JOIN #DF df ON df.UnitName = u.UnitName
JOIN #H rs ON rs.Label = 'sal' JOIN #H rp ON rp.Label = 'pf'
CROSS APPLY (SELECT Raw = (b.Mn + rs.R * 0.5 * (b.Mx - b.Mn)) * df.F * (0.92 + 0.16 * rp.R)) a
CROSS APPLY (SELECT Rounded = CAST(CAST(ROUND(a.Raw / 100.0, 0) AS int) * 100 AS decimal(10,2)),
                    LowB    = CAST(CAST(CEILING(b.Mn * df.F / 100.0) AS int) * 100 AS decimal(10,2)),
                    HighB   = CAST(CAST(FLOOR(b.Mx * df.F / 100.0) AS int) * 100 AS decimal(10,2))) s
WHERE b.JobLevel = @Level;

IF @Unit IS NULL OR @Pos IS NULL OR @Mgr IS NULL OR @Gender IS NULL OR @Nat IS NULL OR @Lang IS NULL OR @First IS NULL OR @Last IS NULL OR @Salary IS NULL
    THROW 50020, 'A new hire could not be completed (no department, position, manager, name or salary).', 1;

-- write the records
DECLARE @Id int = (SELECT ISNULL(MAX(EmployeeID), 0) + 1 FROM dbo.Employees);
DECLARE @Number char(10) = 'EMP-' + RIGHT('000000' + CAST(@Id AS varchar(6)), 6);
SET IDENTITY_INSERT dbo.Employees ON;
INSERT dbo.Employees (EmployeeID, EmployeeNumber, FirstName, LastName, Gender, DateOfBirth, Nationality, NativeLanguage, HireDate,
                      EmailAddress, PositionID, OrganizationUnitID, ManagerEmployeeID, ProfileImageFileName)
VALUES (@Id, @Number, @First, @Last, @Gender, @Dob, @Nat, @Lang, @Date, @Email, @Pos, @Unit, @Mgr, @Number + '.jpg');
SET IDENTITY_INSERT dbo.Employees OFF;
INSERT dbo.EmployeeJobHistory (EmployeeID, EffectiveDate, EndDate, PositionID, OrganizationUnitID, ManagerEmployeeID, ChangeType, Reason)
VALUES (@Id, @Date, NULL, @Pos, @Unit, @Mgr, 'Initial Assignment', N'Hired as ' + @PosTitle);
INSERT dbo.EmployeeCompensationHistory (EmployeeID, EffectiveDate, EndDate, BaseSalary, ChangeReason)
VALUES (@Id, @Date, NULL, @Salary, 'Initial Salary');
INSERT #Hired VALUES (@Id, @Date);

-- a department that is now above its target gets a new target row: the headcount (the old plan rows are never edited)
INSERT dbo.DepartmentWorkforcePlanHistory (OrganizationUnitID, EffectiveDate, TargetHeadcount)
SELECT @Unit, @Date, c.Hc
FROM (SELECT COUNT(*) AS Hc FROM dbo.EmployeeJobHistory WHERE OrganizationUnitID = @Unit AND EndDate IS NULL) c
WHERE c.Hc > (SELECT TOP 1 h.TargetHeadcount FROM dbo.DepartmentWorkforcePlanHistory h WHERE h.OrganizationUnitID = @Unit ORDER BY h.EffectiveDate DESC);

DROP TABLE #H;
SET @Unit = NULL; SET @Pos = NULL; SET @Mgr = NULL; SET @Gender = NULL; SET @Nat = NULL; SET @Lang = NULL; SET @First = NULL; SET @Last = NULL; SET @Salary = NULL;
