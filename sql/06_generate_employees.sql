-- 06_generate_employees.sql: 151 employees in their FINAL state (position, department, manager,
-- demographics, hire date, email). History tables are derived from this later.
-- Deterministic: every random value is a hash of (seed, employee ID, label).
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -f 65001 -i sql/06_generate_employees.sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Seed       varchar(20) = 'DemoHR-2026';
DECLARE @RefDate    date   = '2026-11-16';   -- reference date ("today"); the only place it is written
DECLARE @Founded    date   = '2012-01-01';
DECLARE @LastHire   date   = '2026-09-30';
DECLARE @RecentFrom date   = DATEADD(YEAR, -5, @RefDate);   -- "last 5 years" before the reference date (2021-11-16)
DECLARE @PRecent    float  = 0.45;           -- chance a hire is drawn from the last 5 years (when both ranges are possible)

BEGIN TRANSACTION;

-- ================================================================ planned holders per position
CREATE TABLE #Hold (PositionTitle nvarchar(100) PRIMARY KEY, Holders int NOT NULL);
INSERT INTO #Hold VALUES
(N'Chief Executive Officer',1),
(N'Chief Technology Officer',1),(N'VP Engineering',1),(N'VP Data & IT',1),
(N'Director of Software Engineering',1),(N'Director of Data & Analytics',1),(N'Director of IT Operations',1),
(N'Engineering Manager',3),(N'Data & Analytics Manager',1),(N'IT Operations Manager',1),
(N'Senior Software Engineer',6),(N'Senior Data Analyst',2),(N'Senior Systems Administrator',2),
(N'Software Engineer',9),(N'Data Analyst',3),(N'Systems Administrator',3),
(N'Junior Software Engineer',5),(N'Junior Data Analyst',2),(N'IT Support Specialist',2),
(N'Chief Financial Officer',1),(N'Director of FP&A',1),(N'Director of Accounting',1),
(N'FP&A Manager',1),(N'Accounting Manager',1),(N'Treasury & Controls Manager',1),
(N'Senior Financial Analyst',3),(N'Senior Accountant',3),(N'Financial Analyst',4),(N'Accountant',4),
(N'Junior Financial Analyst',2),(N'Junior Accountant',3),
(N'Chief Human Resources Officer',1),(N'Director of People Operations',1),
(N'Talent Acquisition Manager',1),(N'HR Business Partner Manager',1),
(N'Senior HR Business Partner',2),(N'Senior Recruiter',2),
(N'HR Business Partner',3),(N'Recruiter',3),(N'HR Specialist',2),(N'HR Assistant',2),(N'Junior Recruiter',2),
(N'Chief Revenue Officer',1),(N'VP Sales',1),(N'Director of Enterprise Sales',1),(N'Director of SMB & Partnerships',1),
(N'Enterprise Sales Manager',2),(N'SMB Sales Manager',1),(N'Partnership Manager',1),
(N'Senior Account Executive',6),(N'Senior Sales Operations Analyst',2),
(N'Account Executive',8),(N'Sales Operations Analyst',2),(N'Partnership Specialist',2),
(N'Sales Development Representative',5),(N'Junior Account Executive',2),
(N'Chief Customer Officer',1),(N'Director of Customer Support',1),(N'Director of Customer Success',1),
(N'Support Team Manager',2),(N'Customer Success Team Manager',1),
(N'Senior Support Specialist',3),(N'Senior Customer Success Specialist',2),
(N'Support Specialist',5),(N'Customer Success Specialist',4),
(N'Junior Support Agent',3),(N'Junior Customer Success Associate',2);

IF (SELECT COUNT(*) FROM #Hold h JOIN dbo.Positions p ON p.PositionTitle = h.PositionTitle) <> 67
   OR (SELECT SUM(Holders) FROM #Hold) <> 151
    THROW 50001, 'Holder list does not match the 67 positions / 151 holders.', 1;

-- ================================================================ final state: one row per employee, rank order
CREATE TABLE #Emp (
    EmployeeID int PRIMARY KEY, PositionID int, UnitID int, Title nvarchar(100), Family nvarchar(50),
    LvlRank tinyint, ManagerID int NULL, Gender varchar(10) NULL, Nationality nvarchar(60) NULL, Lang nvarchar(60) NULL,
    FirstName nvarchar(60) NULL, LastName nvarchar(60) NULL, DOB date NULL, HireDate date NULL, EmailBase nvarchar(200) NULL
);

INSERT INTO #Emp (EmployeeID, PositionID, UnitID, Title, Family, LvlRank)
SELECT ROW_NUMBER() OVER (ORDER BY p.JobLevelRank, p.OrganizationUnitID, p.PositionID, s.n),
       p.PositionID, p.OrganizationUnitID, p.PositionTitle, p.JobFamily, p.JobLevelRank
FROM dbo.Positions p
JOIN #Hold h ON h.PositionTitle = p.PositionTitle
JOIN (VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9)) s(n) ON s.n <= h.Holders;

-- ================================================================ deterministic random numbers (0 <= R < 1)
CREATE TABLE #R (EmployeeID int, Label varchar(10), R float, PRIMARY KEY (EmployeeID, Label));
INSERT INTO #R
SELECT e.EmployeeID, l.Label,
       (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|', e.EmployeeID, '|', l.Label)), 1, 4) AS int) & 2147483647) / 2147483648.0
FROM #Emp e
CROSS JOIN (VALUES ('gender'),('nat'),('swe'),('fn'),('ln'),('mgr'),('dob'),('hire1'),('hire2')) l(Label);

-- ================================================================ managers (final state)
-- C-Level reports to the CEO
UPDATE e SET ManagerID = (SELECT EmployeeID FROM #Emp WHERE LvlRank = 1)
FROM #Emp e WHERE e.LvlRank = 2;

-- VP, Director and Manager: by title (each parent title has exactly one holder)
CREATE TABLE #ParentMap (ChildTitle nvarchar(100) PRIMARY KEY, ParentTitle nvarchar(100));
INSERT INTO #ParentMap VALUES
(N'VP Engineering', N'Chief Technology Officer'),(N'VP Data & IT', N'Chief Technology Officer'),(N'VP Sales', N'Chief Revenue Officer'),
(N'Director of Software Engineering', N'VP Engineering'),(N'Director of Data & Analytics', N'VP Data & IT'),(N'Director of IT Operations', N'VP Data & IT'),
(N'Director of FP&A', N'Chief Financial Officer'),(N'Director of Accounting', N'Chief Financial Officer'),
(N'Director of People Operations', N'Chief Human Resources Officer'),
(N'Director of Enterprise Sales', N'VP Sales'),(N'Director of SMB & Partnerships', N'VP Sales'),
(N'Director of Customer Support', N'Chief Customer Officer'),(N'Director of Customer Success', N'Chief Customer Officer'),
(N'Engineering Manager', N'Director of Software Engineering'),(N'Data & Analytics Manager', N'Director of Data & Analytics'),
(N'IT Operations Manager', N'Director of IT Operations'),
(N'FP&A Manager', N'Director of FP&A'),(N'Accounting Manager', N'Director of Accounting'),(N'Treasury & Controls Manager', N'Director of Accounting'),
(N'Talent Acquisition Manager', N'Director of People Operations'),(N'HR Business Partner Manager', N'Director of People Operations'),
(N'Enterprise Sales Manager', N'Director of Enterprise Sales'),(N'SMB Sales Manager', N'Director of SMB & Partnerships'),(N'Partnership Manager', N'Director of SMB & Partnerships'),
(N'Support Team Manager', N'Director of Customer Support'),(N'Customer Success Team Manager', N'Director of Customer Success');

UPDATE e SET ManagerID = p.EmployeeID
FROM #Emp e JOIN #ParentMap m ON m.ChildTitle = e.Title JOIN #Emp p ON p.Title = m.ParentTitle;

-- Senior / Professional / Junior: a Manager of the same department, matched by job family.
-- A family with several managers is split into even chunks (random order); some families share managers to balance team sizes.
CREATE TABLE #StaffMap (Family nvarchar(50), MgrTitle nvarchar(100));
INSERT INTO #StaffMap VALUES
(N'Engineering', N'Engineering Manager'),
(N'Data & Analytics', N'Data & Analytics Manager'),
(N'IT Operations', N'IT Operations Manager'),
(N'Financial Planning & Analysis', N'FP&A Manager'),
(N'Accounting', N'Accounting Manager'),(N'Accounting', N'Treasury & Controls Manager'),
(N'Talent Acquisition', N'Talent Acquisition Manager'),
(N'HR Business Partnering', N'HR Business Partner Manager'),
(N'People Operations', N'Talent Acquisition Manager'),(N'People Operations', N'HR Business Partner Manager'),
(N'Enterprise Sales', N'Enterprise Sales Manager'),(N'Enterprise Sales', N'SMB Sales Manager'),
(N'Sales Operations', N'SMB Sales Manager'),(N'Sales Operations', N'Partnership Manager'),
(N'SMB & Partnerships', N'Partnership Manager'),
(N'Customer Support', N'Support Team Manager'),
(N'Customer Success', N'Customer Success Team Manager');

;WITH cand AS (
    SELECT sm.Family, m.EmployeeID AS MgrID,
           ROW_NUMBER() OVER (PARTITION BY sm.Family ORDER BY m.EmployeeID) AS idx,
           COUNT(*)     OVER (PARTITION BY sm.Family) AS cnt
    FROM #StaffMap sm JOIN #Emp m ON m.Title = sm.MgrTitle
), st AS (
    SELECT e.EmployeeID, e.Family,
           ROW_NUMBER() OVER (PARTITION BY e.Family ORDER BY r.R, e.EmployeeID) AS rn,
           COUNT(*)     OVER (PARTITION BY e.Family) AS total
    FROM #Emp e JOIN #R r ON r.EmployeeID = e.EmployeeID AND r.Label = 'mgr'
    WHERE e.LvlRank >= 6
)
UPDATE e SET ManagerID = c.MgrID
FROM #Emp e JOIN st ON st.EmployeeID = e.EmployeeID
JOIN cand c ON c.Family = st.Family AND c.idx = ((st.rn - 1) * c.cnt / st.total) + 1;

IF EXISTS (SELECT 1 FROM #Emp WHERE LvlRank > 1 AND ManagerID IS NULL)
    THROW 50002, 'Some employees have no manager.', 1;

-- ================================================================ gender: balanced inside every department x level group
;WITH g AS (
    SELECT e.EmployeeID, e.UnitID, e.LvlRank,
           ROW_NUMBER() OVER (PARTITION BY e.UnitID, e.LvlRank ORDER BY r.R, e.EmployeeID) AS pos
    FROM #Emp e JOIN #R r ON r.EmployeeID = e.EmployeeID AND r.Label = 'gender'
), o AS (   -- odd-sized groups take turns having the extra Female / Male
    SELECT UnitID, LvlRank, ROW_NUMBER() OVER (ORDER BY UnitID, LvlRank) AS ord
    FROM #Emp GROUP BY UnitID, LvlRank HAVING COUNT(*) % 2 = 1
)
UPDATE e SET Gender = CASE WHEN (g.pos + ISNULL(o.ord, 0)) % 2 = 0 THEN 'Female' ELSE 'Male' END
FROM #Emp e JOIN g ON g.EmployeeID = e.EmployeeID
LEFT JOIN o ON o.UnitID = g.UnitID AND o.LvlRank = g.LvlRank;

-- ================================================================ nationality (fixed quotas, random order) and native language
CREATE TABLE #Quota (Ord int IDENTITY(1,1), Nationality nvarchar(60), Cnt int);
INSERT INTO #Quota (Nationality, Cnt) VALUES
(N'Finnish',60),(N'Swedish',8),(N'Estonian',8),(N'German',8),(N'Polish',7),(N'British',7),(N'French',6),(N'Spanish',6),
(N'Italian',6),(N'Indian',8),(N'Turkish',6),(N'Nigerian',5),(N'Brazilian',6),(N'Chinese',6),(N'Vietnamese',4);
IF (SELECT SUM(Cnt) FROM #Quota) <> 151 THROW 50003, 'Nationality quotas must sum to 151.', 1;

;WITH q AS (
    SELECT Nationality, SUM(Cnt) OVER (ORDER BY Ord ROWS UNBOUNDED PRECEDING) - Cnt AS CumStart,
           SUM(Cnt) OVER (ORDER BY Ord ROWS UNBOUNDED PRECEDING) AS CumEnd
    FROM #Quota
), s AS (
    SELECT e.EmployeeID, ROW_NUMBER() OVER (ORDER BY r.R, e.EmployeeID) AS n
    FROM #Emp e JOIN #R r ON r.EmployeeID = e.EmployeeID AND r.Label = 'nat'
)
UPDATE e SET Nationality = q.Nationality
FROM #Emp e JOIN s ON s.EmployeeID = e.EmployeeID JOIN q ON s.n > q.CumStart AND s.n <= q.CumEnd;

-- Native language follows nationality; 5% of Finnish nationals (3 of 60) have Swedish
UPDATE e SET Lang = nl.NativeLanguage
FROM #Emp e
JOIN (SELECT DISTINCT Nationality, NativeLanguage FROM dbo.DummyNames
      WHERE NOT (Nationality = N'Finnish' AND NativeLanguage = N'Swedish')) nl ON nl.Nationality = e.Nationality;

;WITH f AS (
    SELECT e.EmployeeID, ROW_NUMBER() OVER (ORDER BY r.R, e.EmployeeID) AS n, COUNT(*) OVER () AS total
    FROM #Emp e JOIN #R r ON r.EmployeeID = e.EmployeeID AND r.Label = 'swe'
    WHERE e.Nationality = N'Finnish'
)
UPDATE e SET Lang = N'Swedish'
FROM #Emp e JOIN f ON f.EmployeeID = e.EmployeeID
WHERE f.n <= ROUND(f.total * 0.05, 0);

-- ================================================================ names (from DummyNames by nationality, language and gender)
;WITH k AS (
    SELECT e.EmployeeID, e.Nationality, e.Lang, e.Gender,
           ROW_NUMBER() OVER (PARTITION BY e.Nationality, e.Lang, e.Gender ORDER BY r.R, e.EmployeeID) AS k
    FROM #Emp e JOIN #R r ON r.EmployeeID = e.EmployeeID AND r.Label = 'fn'
), p AS (
    SELECT d.NameValue, d.Nationality, d.NativeLanguage, d.Gender,
           ROW_NUMBER() OVER (PARTITION BY d.Nationality, d.NativeLanguage, d.Gender ORDER BY HASHBYTES('SHA2_256', CONCAT(@Seed, '|fname|', d.DummyNameID))) AS i,
           COUNT(*)     OVER (PARTITION BY d.Nationality, d.NativeLanguage, d.Gender) AS c
    FROM dbo.DummyNames d WHERE d.NameType = 'First'
)
UPDATE e SET FirstName = p.NameValue
FROM #Emp e JOIN k ON k.EmployeeID = e.EmployeeID
JOIN p ON p.Nationality = k.Nationality AND p.NativeLanguage = k.Lang AND p.Gender = k.Gender AND p.i = ((k.k - 1) % p.c) + 1;

;WITH k AS (
    SELECT e.EmployeeID, e.Nationality, e.Lang,
           ROW_NUMBER() OVER (PARTITION BY e.Nationality, e.Lang ORDER BY r.R, e.EmployeeID) AS k
    FROM #Emp e JOIN #R r ON r.EmployeeID = e.EmployeeID AND r.Label = 'ln'
), p AS (
    SELECT d.NameValue, d.Nationality, d.NativeLanguage,
           ROW_NUMBER() OVER (PARTITION BY d.Nationality, d.NativeLanguage ORDER BY HASHBYTES('SHA2_256', CONCAT(@Seed, '|lname|', d.DummyNameID))) AS i,
           COUNT(*)     OVER (PARTITION BY d.Nationality, d.NativeLanguage) AS c
    FROM dbo.DummyNames d WHERE d.NameType = 'Last'
)
UPDATE e SET LastName = p.NameValue
FROM #Emp e JOIN k ON k.EmployeeID = e.EmployeeID
JOIN p ON p.Nationality = k.Nationality AND p.NativeLanguage = k.Lang AND p.i = ((k.k - 1) % p.c) + 1;

-- ================================================================ date of birth (age on the reference date by level)
CREATE TABLE #Age (LvlRank tinyint PRIMARY KEY, MinAge int, MaxAge int);
INSERT INTO #Age VALUES (1,50,58),(2,44,62),(3,42,60),(4,40,58),(5,34,56),(6,30,52),(7,25,42),(8,22,32);

UPDATE e SET DOB = DATEADD(DAY, CAST(FLOOR(r.R * (DATEDIFF(DAY, x.Oldest, x.Youngest) + 1)) AS int), x.Oldest)
FROM #Emp e
JOIN #Age a ON a.LvlRank = e.LvlRank
CROSS APPLY (SELECT Oldest   = DATEADD(DAY, 1, DATEADD(YEAR, -(a.MaxAge + 1), @RefDate)),
                    Youngest = DATEADD(YEAR, -a.MinAge, @RefDate)) x
JOIN #R r ON r.EmployeeID = e.EmployeeID AND r.Label = 'dob';

-- ================================================================ hire dates, top of the hierarchy first
-- Working days 2012-01-01 .. 2026-09-30 (no weekends, no Finnish public holidays)
CREATE TABLE #WD (Seq int IDENTITY(1,1) PRIMARY KEY, D date NOT NULL UNIQUE);
;WITH d AS (
    SELECT @Founded AS D UNION ALL SELECT DATEADD(DAY, 1, D) FROM d WHERE D < @LastHire
)
INSERT INTO #WD (D)
SELECT D FROM d
WHERE DATEDIFF(DAY, '19000101', D) % 7 < 5                        -- 1900-01-01 was a Monday
  AND NOT EXISTS (SELECT 1 FROM dbo.PublicHolidays h WHERE h.HolidayDate = d.D)
ORDER BY D
OPTION (MAXRECURSION 0);

-- Hire window per level, then a date after the manager's hire date and after the person turned 21.
-- CEO 2012 (first half), C-Level to 2014, VP to 2015, Director to 2016, Manager to 2023 (so teams can be hired later).
DECLARE @lvl int = 1;
WHILE @lvl <= 8
BEGIN
    ;WITH b AS (
        SELECT e.EmployeeID,
               lo = (SELECT MAX(v) FROM (VALUES (@Founded), (DATEADD(DAY, 1, m.HireDate)), (DATEADD(YEAR, 21, e.DOB))) t(v)),
               hi = CASE e.LvlRank WHEN 1 THEN CAST('2012-06-30' AS date) WHEN 2 THEN CAST('2014-12-31' AS date)
                                   WHEN 3 THEN CAST('2015-12-31' AS date) WHEN 4 THEN CAST('2016-12-31' AS date)
                                   WHEN 5 THEN CAST('2023-12-31' AS date) ELSE @LastHire END,
               ra = r1.R, rb = r2.R
        FROM #Emp e
        LEFT JOIN #Emp m ON m.EmployeeID = e.ManagerID
        JOIN #R r1 ON r1.EmployeeID = e.EmployeeID AND r1.Label = 'hire1'
        JOIN #R r2 ON r2.EmployeeID = e.EmployeeID AND r2.Label = 'hire2'
        WHERE e.LvlRank = @lvl
    ), w AS (
        SELECT b.*,
               oldHi = CASE WHEN hi < @RecentFrom THEN hi ELSE DATEADD(DAY, -1, @RecentFrom) END,
               recLo = CASE WHEN lo > @RecentFrom THEN lo ELSE @RecentFrom END
        FROM b
    ), ix AS (
        SELECT w.*,
               oLo = (SELECT MIN(Seq) FROM #WD WHERE D >= w.lo),
               oHi = (SELECT MAX(Seq) FROM #WD WHERE D <= w.oldHi),
               rLo = (SELECT MIN(Seq) FROM #WD WHERE D >= w.recLo),
               rHi = (SELECT MAX(Seq) FROM #WD WHERE D <= w.hi)
        FROM w
    ), c AS (
        SELECT ix.*,
               useRec = CASE WHEN rLo <= rHi AND (NOT (oLo <= oHi) OR oLo IS NULL OR oHi IS NULL OR ra < @PRecent) THEN 1
                             WHEN oLo <= oHi THEN 0 END
        FROM ix
    )
    UPDATE e SET HireDate = (SELECT D FROM #WD
                             WHERE Seq = CASE WHEN c.useRec = 1 THEN c.rLo + CAST(FLOOR(c.rb * (c.rHi - c.rLo + 1)) AS int)
                                              ELSE c.oLo + CAST(FLOOR(c.rb * (c.oHi - c.oLo + 1)) AS int) END)
    FROM #Emp e JOIN c ON c.EmployeeID = e.EmployeeID;
    SET @lvl += 1;
END;

IF EXISTS (SELECT 1 FROM #Emp WHERE HireDate IS NULL OR DOB IS NULL OR FirstName IS NULL OR LastName IS NULL OR Gender IS NULL)
    THROW 50004, 'Some employees are incomplete (no hire date, name or gender).', 1;

-- ================================================================ email: firstname.lastname@acmecorp.example, accents removed
CREATE TABLE #Acc (Ch nvarchar(1) COLLATE Latin1_General_BIN2, Rep varchar(1));
INSERT INTO #Acc VALUES
(N'ä','a'),(N'ö','o'),(N'å','a'),(N'ü','u'),(N'õ','o'),(N'é','e'),(N'è','e'),(N'ê','e'),(N'ë','e'),(N'á','a'),(N'à','a'),(N'â','a'),(N'ã','a'),
(N'í','i'),(N'ì','i'),(N'ó','o'),(N'ô','o'),(N'ú','u'),(N'ù','u'),(N'ç','c'),(N'ñ','n'),(N'ł','l'),(N'ś','s'),(N'ż','z'),(N'ź','z'),
(N'ć','c'),(N'ń','n'),(N'ę','e'),(N'ą','a'),(N'ı','i'),(N'ş','s'),(N'ğ','g'),(N'š','s'),(N'ž','z'),(N'đ','d'),
(N'ễ','e'),(N'ầ','a'),(N'ạ','a'),(N'ỳ','y'),(N'ũ','u'),(N'ơ','o'),(N'ư','u'),(N'ý','y');

UPDATE #Emp SET EmailBase = LOWER(FirstName) + N'.' + LOWER(LastName);
DECLARE @ch nvarchar(1), @rep varchar(1);
DECLARE accs CURSOR LOCAL FAST_FORWARD FOR SELECT Ch, Rep FROM #Acc ORDER BY Ch;
OPEN accs; FETCH NEXT FROM accs INTO @ch, @rep;
WHILE @@FETCH_STATUS = 0
BEGIN
    UPDATE #Emp SET EmailBase = REPLACE(EmailBase COLLATE Latin1_General_BIN2, @ch, @rep);
    FETCH NEXT FROM accs INTO @ch, @rep;
END
CLOSE accs; DEALLOCATE accs;

-- ================================================================ write to Employees (clears only this table)
DELETE FROM dbo.Employees;
DECLARE @seedEmp int = CASE WHEN EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.Employees') AND last_value IS NULL) THEN 1 ELSE 0 END;
DBCC CHECKIDENT ('dbo.Employees', RESEED, @seedEmp) WITH NO_INFOMSGS;

SET IDENTITY_INSERT dbo.Employees ON;
INSERT INTO dbo.Employees (EmployeeID, EmployeeNumber, FirstName, LastName, Gender, DateOfBirth, Nationality, NativeLanguage,
                           HireDate, EmailAddress, PositionID, OrganizationUnitID, ManagerEmployeeID, ProfileImageFileName)
SELECT e.EmployeeID, 'EMP-' + RIGHT('000000' + CAST(e.EmployeeID AS varchar(6)), 6), e.FirstName, e.LastName, e.Gender, e.DOB,
       e.Nationality, e.Lang, e.HireDate,
       e.EmailBase + CASE WHEN d.dup = 1 THEN N'' ELSE N'.' + CAST(d.dup AS nvarchar(5)) END + N'@acmecorp.example',
       e.PositionID, e.UnitID, e.ManagerID, NULL
FROM #Emp e
JOIN (SELECT EmployeeID, ROW_NUMBER() OVER (PARTITION BY EmailBase ORDER BY EmployeeID) AS dup FROM #Emp) d ON d.EmployeeID = e.EmployeeID
ORDER BY e.EmployeeID;
SET IDENTITY_INSERT dbo.Employees OFF;
DBCC CHECKIDENT ('dbo.Employees', RESEED, 151) WITH NO_INFOMSGS;

COMMIT TRANSACTION;

-- ================================================================ checks (still inside the same batch: planned holders are in #Hold)
PRINT '--- 1. Rows, numbers, emails';
SELECT COUNT(*) AS Employees, COUNT(DISTINCT EmployeeNumber) AS DistinctNumbers, MIN(EmployeeNumber) AS FirstNumber, MAX(EmployeeNumber) AS LastNumber,
       COUNT(DISTINCT EmailAddress) AS DistinctEmails,
       SUM(CASE WHEN EmailAddress COLLATE Latin1_General_BIN2 LIKE '%[^a-z0-9.@]%' OR EmailAddress NOT LIKE '%@acmecorp.example' THEN 1 ELSE 0 END) AS BadEmails,
       SUM(CASE WHEN EmailAddress LIKE '%.[0-9]@%' THEN 1 ELSE 0 END) AS EmailsWithSuffix
FROM dbo.Employees;

PRINT '--- 2. Headcount per department vs plan (CEO sits under Acme Corporation)';
SELECT u.UnitName, COUNT(e.EmployeeID) AS Actual, w.TargetHeadcount AS Target,
       CASE WHEN w.TargetHeadcount IS NULL THEN CASE WHEN COUNT(e.EmployeeID) = 1 THEN 'OK' ELSE 'DIFF' END
            WHEN w.TargetHeadcount = COUNT(e.EmployeeID) THEN 'OK'
            WHEN w.TargetHeadcount > COUNT(e.EmployeeID) THEN 'BELOW TARGET (open positions in the plan)' ELSE 'OVER TARGET' END AS Status
FROM dbo.OrganizationUnits u
LEFT JOIN dbo.Employees e ON e.OrganizationUnitID = u.OrganizationUnitID
LEFT JOIN dbo.DepartmentWorkforcePlan w ON w.OrganizationUnitID = u.OrganizationUnitID
GROUP BY u.OrganizationUnitID, u.UnitName, w.TargetHeadcount ORDER BY u.OrganizationUnitID;

PRINT '--- 3. Positions whose headcount differs from the plan (expect 0) and employees in the wrong department (expect 0)';
SELECT (SELECT COUNT(*) FROM dbo.Positions p JOIN #Hold h ON h.PositionTitle = p.PositionTitle
        WHERE h.Holders <> (SELECT COUNT(*) FROM dbo.Employees e WHERE e.PositionID = p.PositionID)) AS PositionMismatches,
       (SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID
        WHERE p.OrganizationUnitID <> e.OrganizationUnitID) AS DepartmentMismatches;

PRINT '--- 4. Headcount by level (expect 1/5/3/10/17/33/52/30)';
SELECT p.JobLevelRank, p.JobLevel, COUNT(*) AS Headcount
FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID GROUP BY p.JobLevelRank, p.JobLevel ORDER BY p.JobLevelRank;

PRINT '--- 5. Gender balance (Female %): overall, by department, by level';
SELECT 'All' AS Grp, COUNT(*) AS N, SUM(CASE WHEN Gender = 'Female' THEN 1 ELSE 0 END) AS Female, CAST(100.0 * SUM(CASE WHEN Gender = 'Female' THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,1)) AS PctFemale FROM dbo.Employees
UNION ALL
SELECT u.UnitName, COUNT(*), SUM(CASE WHEN Gender = 'Female' THEN 1 ELSE 0 END), CAST(100.0 * SUM(CASE WHEN Gender = 'Female' THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,1))
FROM dbo.Employees e JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = e.OrganizationUnitID GROUP BY u.OrganizationUnitID, u.UnitName
UNION ALL
SELECT p.JobLevel, COUNT(*), SUM(CASE WHEN Gender = 'Female' THEN 1 ELSE 0 END), CAST(100.0 * SUM(CASE WHEN Gender = 'Female' THEN 1 ELSE 0 END) / COUNT(*) AS decimal(5,1))
FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID GROUP BY p.JobLevelRank, p.JobLevel;

PRINT '--- 6. Nationality (Finnish about 40%, none other above 10%) and native language';
SELECT Nationality, NativeLanguage, COUNT(*) AS N, CAST(100.0 * COUNT(*) / 151 AS decimal(4,1)) AS Pct
FROM dbo.Employees GROUP BY Nationality, NativeLanguage ORDER BY COUNT(*) DESC, Nationality;

PRINT '--- 7. Age by level vs allowed range, hire age, hire window (all violation counts expect 0)';
SELECT (SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID JOIN #Age a ON a.LvlRank = p.JobLevelRank
        CROSS APPLY (SELECT Age = DATEDIFF(YEAR, e.DateOfBirth, @RefDate) - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, e.DateOfBirth, @RefDate), e.DateOfBirth) > @RefDate THEN 1 ELSE 0 END) x
        WHERE x.Age < a.MinAge OR x.Age > a.MaxAge) AS AgeOutOfRange,
       (SELECT COUNT(*) FROM dbo.Employees WHERE HireDate < DATEADD(YEAR, 21, DateOfBirth)) AS HiredBefore21,
       (SELECT COUNT(*) FROM dbo.Employees WHERE HireDate < '2012-01-01' OR HireDate > '2026-09-30') AS OutsideHireWindow,
       (SELECT COUNT(*) FROM dbo.Employees e WHERE DATEDIFF(DAY, '19000101', HireDate) % 7 >= 5
              OR EXISTS (SELECT 1 FROM dbo.PublicHolidays h WHERE h.HolidayDate = e.HireDate)) AS HiredOnNonWorkingDay,
       (SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.Employees m ON m.EmployeeID = e.ManagerEmployeeID WHERE e.HireDate <= m.HireDate) AS HiredNotAfterManager;

PRINT '--- 8. Hire years: CEO/C-Level 2012-2014, VP/Director 2012-2016; share hired in the last 5 years (about 60%)';
SELECT p.JobLevel, MIN(YEAR(e.HireDate)) AS FirstYear, MAX(YEAR(e.HireDate)) AS LastYear
FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID GROUP BY p.JobLevelRank, p.JobLevel ORDER BY p.JobLevelRank;
SELECT SUM(CASE WHEN HireDate >= @RecentFrom THEN 1 ELSE 0 END) AS HiredLast5Years,
       CAST(100.0 * SUM(CASE WHEN HireDate >= @RecentFrom THEN 1 ELSE 0 END) / COUNT(*) AS decimal(4,1)) AS PctLast5Years
FROM dbo.Employees;

PRINT '--- 9. Same first+last name (expect 0 or few; emails stay unique with .2 suffix)';
SELECT COUNT(*) AS DuplicateFullNames FROM (SELECT FirstName, LastName FROM dbo.Employees GROUP BY FirstName, LastName HAVING COUNT(*) > 1) d;

DROP TABLE #Hold, #Emp, #R, #ParentMap, #StaffMap, #Quota, #Age, #WD, #Acc;
GO
