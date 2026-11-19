-- 09_generate_compensation.sql: salary history for all 151 employees, built BACKWARDS from today's salary
-- and aligned with EmployeeJobHistory (script 08).
-- Deterministic: every random value is a hash of (seed, employee ID, label).
--
-- Today's salary = level band x department factor x personal factor (0.92-1.08), rounded to 100 EUR.
-- The band base is drawn from [min/0.92, max/1.08] so that, after the personal factor, the salary always
-- stays inside [band min x department factor, band max x department factor].
-- Salary records start on:
--   * the hire date (Initial Salary),
--   * every Promotion and Promotion + Department Transfer date of the job history (Promotion, raise 6-12%),
--   * every plain Department Transfer date (Department Transfer, 0-4%, at least 100 EUR),
--   * every 1 January from 6 months after hire (Annual Increase, 1.5-4.5%; skipped if a promotion or transfer
--     already changes pay on that 1 January),
--   * one Market Adjustment (4-8%) for about 5% of employees, on an April, July or October quarter start.
-- All salaries are multiples of 100 EUR; going backwards each step is chosen so that the realised change
-- lies inside its percentage range, so salaries never decrease.
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -f 65001 -i sql/09_generate_compensation.sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Seed      varchar(20) = 'DemoHR-2026';
DECLARE @RefDate   date        = '2026-11-16';   -- reference date ("today"); the only place it is written
DECLARE @LastEvent date        = '2026-07-01';   -- last quarter start before 2026-10-01 (same cutoff as the job history)
DECLARE @pMarket   float       = 0.05;           -- share of employees with one Market Adjustment

BEGIN TRANSACTION;

-- ================================================================ reference tables (script-local)
CREATE TABLE #Band  (JobLevel varchar(20) PRIMARY KEY, Mn decimal(10,2), Mx decimal(10,2));
INSERT INTO #Band VALUES ('CEO',280000,340000),('C-Level',160000,240000),('VP',125000,165000),('Director',95000,130000),
                         ('Manager',72000,98000),('Senior',58000,78000),('Professional',44000,58000),('Junior',33000,43000);
CREATE TABLE #DF    (UnitName nvarchar(100) PRIMARY KEY, F decimal(4,2));
INSERT INTO #DF VALUES (N'Acme Corporation',1.00),(N'Technology',1.08),(N'Finance',1.03),(N'Human Resources',0.95),(N'Sales',1.00),(N'Customer Experience',0.93);
CREATE TABLE #Ratio (Reason varchar(40) PRIMARY KEY, Lo decimal(6,4), Hi decimal(6,4));
INSERT INTO #Ratio VALUES ('Annual Increase',1.015,1.045),('Promotion',1.06,1.12),('Market Adjustment',1.04,1.08),('Department Transfer',1.002,1.04);

-- ================================================================ today's salary
CREATE TABLE #E (EmployeeID int PRIMARY KEY, HireDate date, UnitID int, Gender varchar(10), JobLevel varchar(20), LvlRank int,
                 F decimal(4,2), Mn decimal(10,2), Mx decimal(10,2), Cur decimal(10,2) NULL);
INSERT INTO #E (EmployeeID, HireDate, UnitID, Gender, JobLevel, LvlRank, F, Mn, Mx)
SELECT e.EmployeeID, e.HireDate, e.OrganizationUnitID, e.Gender, p.JobLevel, p.JobLevelRank,
       CASE WHEN p.JobLevelRank = 1 THEN 1.00 ELSE df.F END, b.Mn, b.Mx
FROM dbo.Employees e
JOIN dbo.Positions p ON p.PositionID = e.PositionID
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = e.OrganizationUnitID
JOIN #DF df ON df.UnitName = u.UnitName
JOIN #Band b ON b.JobLevel = p.JobLevel;

CREATE TABLE #R (EmployeeID int, Label varchar(10), R float, PRIMARY KEY (EmployeeID, Label));
INSERT INTO #R
SELECT x.EmployeeID, l.Label,
       (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|comp|', x.EmployeeID, '|', l.Label)), 1, 4) AS int) & 2147483647) / 2147483648.0
FROM #E x CROSS JOIN (VALUES ('base'),('pf'),('mkt'),('mkd')) l(Label);

UPDATE x SET Cur =
    CASE WHEN s.Rounded < s.LowB THEN s.LowB WHEN s.Rounded > s.HighB THEN s.HighB ELSE s.Rounded END
FROM #E x
JOIN #R rb ON rb.EmployeeID = x.EmployeeID AND rb.Label = 'base'
JOIN #R rp ON rp.EmployeeID = x.EmployeeID AND rp.Label = 'pf'
CROSS APPLY (SELECT Raw = (x.Mn / 0.92 + rb.R * (x.Mx / 1.08 - x.Mn / 0.92)) * x.F * (0.92 + 0.16 * rp.R)) a
CROSS APPLY (SELECT Rounded = CAST(CAST(ROUND(a.Raw / 100.0, 0) AS int) * 100 AS decimal(10,2)),
                    LowB    = CAST(CAST(CEILING(x.Mn * x.F / 100.0) AS int) * 100 AS decimal(10,2)),
                    HighB   = CAST(CAST(FLOOR(x.Mx * x.F / 100.0) AS int) * 100 AS decimal(10,2))) s;

-- ================================================================ salary records (dates and reasons), salaries filled in below
CREATE TABLE #Rec (EmployeeID int, Eff date, Reason varchar(40), Salary decimal(10,2) NULL, Dr int NULL, PRIMARY KEY (EmployeeID, Eff));

-- 1. initial salary on the hire date
INSERT INTO #Rec (EmployeeID, Eff, Reason) SELECT EmployeeID, HireDate, 'Initial Salary' FROM #E;

-- 2. promotions and plain transfers from the job history (same date)
INSERT INTO #Rec (EmployeeID, Eff, Reason)
SELECT EmployeeID, EffectiveDate,
       CASE WHEN ChangeType IN ('Promotion', 'Promotion + Department Transfer') THEN 'Promotion' ELSE 'Department Transfer' END
FROM dbo.EmployeeJobHistory
WHERE ChangeType IN ('Promotion', 'Promotion + Department Transfer', 'Department Transfer');

-- 3. annual increase on 1 January: at least 6 months of service, not later than the reference date, not on a promotion/transfer date
;WITH yrs AS (SELECT 2012 AS Y UNION ALL SELECT Y + 1 FROM yrs WHERE Y < YEAR(@RefDate))
INSERT INTO #Rec (EmployeeID, Eff, Reason)
SELECT x.EmployeeID, DATEFROMPARTS(y.Y, 1, 1), 'Annual Increase'
FROM #E x CROSS JOIN yrs y
WHERE DATEFROMPARTS(y.Y, 1, 1) >= DATEADD(MONTH, 6, x.HireDate)
  AND DATEFROMPARTS(y.Y, 1, 1) <= @RefDate
  AND NOT EXISTS (SELECT 1 FROM #Rec r WHERE r.EmployeeID = x.EmployeeID AND r.Eff = DATEFROMPARTS(y.Y, 1, 1));

-- 4. market adjustment for about 5%: an April / July / October quarter start, 6+ months after hire, on a free date
;WITH qd AS (
    SELECT DATEFROMPARTS(y.Y, m.M, 1) AS D FROM (VALUES (2012),(2013),(2014),(2015),(2016),(2017),(2018),(2019),(2020),(2021),(2022),(2023),(2024),(2025),(2026)) y(Y)
    CROSS JOIN (VALUES (4),(7),(10)) m(M)
), pick AS (
    SELECT x.EmployeeID, qd.D,
           ROW_NUMBER() OVER (PARTITION BY x.EmployeeID ORDER BY HASHBYTES('SHA2_256', CONCAT(@Seed, '|mkd|', x.EmployeeID, '|', CONVERT(varchar(10), qd.D, 120)))) AS rn
    FROM #E x
    JOIN #R rm ON rm.EmployeeID = x.EmployeeID AND rm.Label = 'mkt' AND rm.R < @pMarket
    JOIN qd ON qd.D >= DATEADD(MONTH, 6, x.HireDate) AND qd.D <= @LastEvent AND qd.D <= @RefDate
    WHERE NOT EXISTS (SELECT 1 FROM #Rec r WHERE r.EmployeeID = x.EmployeeID AND r.Eff = qd.D)
)
INSERT INTO #Rec (EmployeeID, Eff, Reason) SELECT EmployeeID, D, 'Market Adjustment' FROM pick WHERE rn = 1;

-- Dr = 0 is the newest record (today's salary), counting back in time
UPDATE r SET Dr = n.Dr
FROM #Rec r JOIN (SELECT EmployeeID, Eff, ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY Eff DESC) - 1 AS Dr FROM #Rec) n
     ON n.EmployeeID = r.EmployeeID AND n.Eff = r.Eff;
UPDATE r SET Salary = x.Cur FROM #Rec r JOIN #E x ON x.EmployeeID = r.EmployeeID WHERE r.Dr = 0;

-- ================================================================ build salaries backwards, one step at a time
-- The record at Dr = d-1 was created by an event with a percentage range; the salary before it (Dr = d) is a multiple of 100
-- chosen inside [after / high ratio, after / low ratio].
DECLARE @d int = 1, @maxd int = (SELECT MAX(Dr) FROM #Rec);
WHILE @d <= @maxd
BEGIN
    ;WITH s AS (
        SELECT r.EmployeeID, r.Eff,
               LowB  = CAST(CEILING(n.Salary / rt.Hi / 100.0) AS int) * 100,
               HighB = CAST(FLOOR(n.Salary / rt.Lo / 100.0) AS int) * 100,
               Rnd   = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|sal|', r.EmployeeID, '|', @d)), 1, 4) AS int) & 2147483647) / 2147483648.0
        FROM #Rec r
        JOIN #Rec n ON n.EmployeeID = r.EmployeeID AND n.Dr = r.Dr - 1
        JOIN #Ratio rt ON rt.Reason = n.Reason
        WHERE r.Dr = @d
    )
    UPDATE r SET Salary = s.LowB + 100 * CAST(FLOOR(s.Rnd * ((s.HighB - s.LowB) / 100 + 1)) AS int)
    FROM #Rec r JOIN s ON s.EmployeeID = r.EmployeeID AND s.Eff = r.Eff;
    IF EXISTS (SELECT 1 FROM #Rec r JOIN #Rec n ON n.EmployeeID = r.EmployeeID AND n.Dr = r.Dr - 1
               JOIN #Ratio rt ON rt.Reason = n.Reason WHERE r.Dr = @d AND CEILING(n.Salary / rt.Hi / 100.0) > FLOOR(n.Salary / rt.Lo / 100.0))
        THROW 50009, 'No whole-100 salary fits a percentage range.', 1;
    SET @d += 1;
END

IF EXISTS (SELECT 1 FROM #Rec WHERE Salary IS NULL OR Salary <= 0) THROW 50010, 'Some salaries could not be built.', 1;

-- ================================================================ write to EmployeeCompensationHistory (clears only this table)
DELETE FROM dbo.EmployeeCompensationHistory;
DECLARE @seedCh int = CASE WHEN EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.EmployeeCompensationHistory') AND last_value IS NULL) THEN 1 ELSE 0 END;
DBCC CHECKIDENT ('dbo.EmployeeCompensationHistory', RESEED, @seedCh) WITH NO_INFOMSGS;

INSERT INTO dbo.EmployeeCompensationHistory (EmployeeID, EffectiveDate, EndDate, BaseSalary, ChangeReason)
SELECT EmployeeID, Eff, LEAD(Eff) OVER (PARTITION BY EmployeeID ORDER BY Eff), Salary, Reason
FROM #Rec
ORDER BY EmployeeID, Eff;

COMMIT TRANSACTION;

-- ================================================================ checks
PRINT '--- 1. One open record per employee';
SELECT COUNT(*) AS Records, COUNT(DISTINCT EmployeeID) AS EmployeesWithPay,
       SUM(CASE WHEN EndDate IS NULL THEN 1 ELSE 0 END) AS OpenRecords,
       (SELECT COUNT(*) FROM (SELECT EmployeeID FROM dbo.EmployeeCompensationHistory WHERE EndDate IS NULL GROUP BY EmployeeID HAVING COUNT(*) <> 1) z) AS EmployeesNotExactlyOneOpen,
       (SELECT COUNT(*) FROM dbo.Employees e WHERE NOT EXISTS (SELECT 1 FROM dbo.EmployeeCompensationHistory c WHERE c.EmployeeID = e.EmployeeID AND c.EndDate IS NULL)) AS EmployeesWithoutOpen
FROM dbo.EmployeeCompensationHistory;

PRINT '--- 2. No gaps or overlaps (EndDate = next EffectiveDate), last record open (violations, expect 0)';
;WITH j AS (SELECT c.*, LEAD(EffectiveDate) OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate) AS NextEff FROM dbo.EmployeeCompensationHistory c)
SELECT (SELECT COUNT(*) FROM j WHERE NextEff IS NOT NULL AND ISNULL(EndDate, '9999-12-31') <> NextEff) AS GapsOrOverlaps,
       (SELECT COUNT(*) FROM j WHERE NextEff IS NULL AND EndDate IS NOT NULL) AS LastRecordClosed,
       (SELECT COUNT(*) FROM j WHERE EndDate IS NOT NULL AND EndDate <= EffectiveDate) AS BadPeriods;

PRINT '--- 3. First record on the hire date with reason Initial Salary; no other Initial Salary (violations, expect 0)';
;WITH j AS (SELECT c.*, ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate) AS rn FROM dbo.EmployeeCompensationHistory c)
SELECT (SELECT COUNT(*) FROM j JOIN dbo.Employees e ON e.EmployeeID = j.EmployeeID WHERE j.rn = 1 AND (j.EffectiveDate <> e.HireDate OR j.ChangeReason <> 'Initial Salary')) AS FirstRecordWrong,
       (SELECT COUNT(*) FROM j WHERE rn > 1 AND ChangeReason = 'Initial Salary') AS ExtraInitialSalary;

PRINT '--- 4. Current salary inside its level band after the department factor (violations, expect 0)';
SELECT COUNT(*) AS Employees,
       SUM(CASE WHEN c.BaseSalary < x.Mn * x.F OR c.BaseSalary > x.Mx * x.F THEN 1 ELSE 0 END) AS OutsideBand,
       SUM(CASE WHEN c.BaseSalary % 100 <> 0 THEN 1 ELSE 0 END) AS NotMultipleOf100,
       MIN(c.BaseSalary / (x.Mn * x.F)) AS MinPosVsBandMin, MAX(c.BaseSalary / (x.Mx * x.F)) AS MaxPosVsBandMax
FROM dbo.EmployeeCompensationHistory c JOIN #E x ON x.EmployeeID = c.EmployeeID WHERE c.EndDate IS NULL;

PRINT '--- 5. Every promotion has a salary change on the same date with reason Promotion, and vice versa (violations, expect 0)';
SELECT (SELECT COUNT(*) FROM dbo.EmployeeJobHistory h WHERE h.ChangeType IN ('Promotion', 'Promotion + Department Transfer')
        AND NOT EXISTS (SELECT 1 FROM dbo.EmployeeCompensationHistory c WHERE c.EmployeeID = h.EmployeeID AND c.EffectiveDate = h.EffectiveDate AND c.ChangeReason = 'Promotion')) AS PromotionsWithoutRaise,
       (SELECT COUNT(*) FROM dbo.EmployeeCompensationHistory c WHERE c.ChangeReason = 'Promotion'
        AND NOT EXISTS (SELECT 1 FROM dbo.EmployeeJobHistory h WHERE h.EmployeeID = c.EmployeeID AND h.EffectiveDate = c.EffectiveDate AND h.ChangeType IN ('Promotion', 'Promotion + Department Transfer'))) AS PromotionRaisesWithoutPromotion,
       (SELECT COUNT(*) FROM dbo.EmployeeJobHistory h WHERE h.ChangeType IN ('Promotion', 'Promotion + Department Transfer')) AS Promotions;

PRINT '--- 6. Salary changes by reason: realised % change (annual increases must be on 1 January, 1.5% to 4.5%)';
;WITH c AS (
    SELECT c.*, LAG(BaseSalary) OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate) AS PrevSalary
    FROM dbo.EmployeeCompensationHistory c)
SELECT ChangeReason, COUNT(*) AS Changes,
       CAST(MIN(100.0 * (BaseSalary / PrevSalary - 1)) AS decimal(5,2)) AS MinPct,
       CAST(AVG(100.0 * (BaseSalary / PrevSalary - 1)) AS decimal(5,2)) AS AvgPct,
       CAST(MAX(100.0 * (BaseSalary / PrevSalary - 1)) AS decimal(5,2)) AS MaxPct,
       SUM(CASE WHEN ChangeReason = 'Annual Increase' AND (MONTH(EffectiveDate) <> 1 OR DAY(EffectiveDate) <> 1 OR BaseSalary / PrevSalary < 1.015 OR BaseSalary / PrevSalary > 1.045) THEN 1 ELSE 0 END) AS AnnualViolations
FROM c WHERE PrevSalary IS NOT NULL GROUP BY ChangeReason ORDER BY MIN(EffectiveDate);

PRINT '--- 7. No salary decreases; no change without a raise; annual increases only with 6+ months of service (violations, expect 0)';
;WITH c AS (SELECT c.*, LAG(BaseSalary) OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate) AS PrevSalary FROM dbo.EmployeeCompensationHistory c)
SELECT (SELECT COUNT(*) FROM c WHERE PrevSalary IS NOT NULL AND BaseSalary < PrevSalary) AS Decreases,
       (SELECT COUNT(*) FROM c WHERE PrevSalary IS NOT NULL AND BaseSalary = PrevSalary) AS ChangesWithoutRaise,
       (SELECT COUNT(*) FROM c JOIN dbo.Employees e ON e.EmployeeID = c.EmployeeID WHERE c.ChangeReason = 'Annual Increase' AND c.EffectiveDate < DATEADD(MONTH, 6, e.HireDate)) AS IncreaseBefore6Months,
       (SELECT COUNT(*) FROM c WHERE EffectiveDate > @RefDate) AS AfterReferenceDate,
       (SELECT COUNT(DISTINCT EmployeeID) FROM dbo.EmployeeCompensationHistory WHERE ChangeReason = 'Market Adjustment') AS EmployeesWithMarketAdjustment,
       (SELECT COUNT(*) FROM dbo.EmployeeCompensationHistory WHERE ChangeReason = 'Department Transfer') AS TransferRecords;

PRINT '--- 8. Average current salary by level, department and gender (EUR)';
SELECT u.UnitName AS Department, x.JobLevel AS Level,
       SUM(CASE WHEN x.Gender = 'Female' THEN 1 ELSE 0 END) AS FemaleN,
       CAST(AVG(CASE WHEN x.Gender = 'Female' THEN c.BaseSalary END) AS decimal(10,0)) AS FemaleAvg,
       SUM(CASE WHEN x.Gender = 'Male' THEN 1 ELSE 0 END) AS MaleN,
       CAST(AVG(CASE WHEN x.Gender = 'Male' THEN c.BaseSalary END) AS decimal(10,0)) AS MaleAvg,
       CAST(AVG(c.BaseSalary) AS decimal(10,0)) AS AllAvg
FROM #E x JOIN dbo.EmployeeCompensationHistory c ON c.EmployeeID = x.EmployeeID AND c.EndDate IS NULL
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = x.UnitID
GROUP BY u.OrganizationUnitID, u.UnitName, x.LvlRank, x.JobLevel ORDER BY u.OrganizationUnitID, x.LvlRank;

PRINT '--- 8b. Average current salary by level and gender (all departments)';
SELECT x.JobLevel AS Level, SUM(CASE WHEN x.Gender = 'Female' THEN 1 ELSE 0 END) AS FemaleN, CAST(AVG(CASE WHEN x.Gender = 'Female' THEN c.BaseSalary END) AS decimal(10,0)) AS FemaleAvg,
       SUM(CASE WHEN x.Gender = 'Male' THEN 1 ELSE 0 END) AS MaleN, CAST(AVG(CASE WHEN x.Gender = 'Male' THEN c.BaseSalary END) AS decimal(10,0)) AS MaleAvg,
       CAST(AVG(c.BaseSalary) AS decimal(10,0)) AS AllAvg
FROM #E x JOIN dbo.EmployeeCompensationHistory c ON c.EmployeeID = x.EmployeeID AND c.EndDate IS NULL
GROUP BY x.LvlRank, x.JobLevel ORDER BY x.LvlRank;

PRINT '--- 8c. Average current salary by department and gender (all levels)';
SELECT u.UnitName AS Department, SUM(CASE WHEN x.Gender = 'Female' THEN 1 ELSE 0 END) AS FemaleN, CAST(AVG(CASE WHEN x.Gender = 'Female' THEN c.BaseSalary END) AS decimal(10,0)) AS FemaleAvg,
       SUM(CASE WHEN x.Gender = 'Male' THEN 1 ELSE 0 END) AS MaleN, CAST(AVG(CASE WHEN x.Gender = 'Male' THEN c.BaseSalary END) AS decimal(10,0)) AS MaleAvg,
       CAST(AVG(c.BaseSalary) AS decimal(10,0)) AS AllAvg
FROM #E x JOIN dbo.EmployeeCompensationHistory c ON c.EmployeeID = x.EmployeeID AND c.EndDate IS NULL
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = x.UnitID
GROUP BY u.OrganizationUnitID, u.UnitName ORDER BY u.OrganizationUnitID;

DROP TABLE #Band, #DF, #Ratio, #E, #R, #Rec;
GO
