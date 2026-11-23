-- 04b_quarter.sql: job changes and pay changes on a quarter start @Date (included inside the loop of 04_run_calendar.sql, no GO)
-- Rules (the forward-looking version of 08_generate_job_history.sql and 09_generate_compensation.sql); every random value is a hash of
-- (seed, date, employee, label), so the result does not depend on how often the update runs:
--   Promotion            Junior to Professional and Professional to Senior, in the same department and job family (so the manager stays),
--                        about 10% of the eligible people a year (2.5% a quarter). Pay rises 6-12%, a multiple of 100 EUR, inside the new
--                        level band times the department factor.
--   Department Transfer  same level, to a department that is below its workforce target (one person per department and quarter),
--                        about 1.6% of the eligible people a year (0.4% a quarter), to a position of that level there, under the manager of
--                        the same job family with the smallest team. Pay rises 0.2-4% (at least 100 EUR) inside the new band.
--   Eligible             Senior, Professional or Junior, 6+ months after hire, no other job change in the last 18 months.
--   Annual Increase      every 1 January: everyone with 6+ months of service, 1.5-4.5%, a multiple of 100 EUR, inside the band; skipped when
--                        a promotion or transfer already changes the pay that day or when the band leaves no room.
--   Market Adjustment    April, July and October: 0.3% of the people with 6+ months of service and no earlier market adjustment, 4-8%.
-- State is read from the open job-history and pay rows. A change fills the EndDate of the open rows (the quarter start) and inserts new open
-- rows. The Employees rows are not touched. Nothing else in the old rows changes.
DECLARE @pPromo float = 0.025, @pXfer float = 0.004, @pMkt float = 0.003;
DECLARE @QKey varchar(8) = CONVERT(varchar(8), @Date, 112);

IF OBJECT_ID(N'tempdb..#C') IS NOT NULL DROP TABLE #C;
CREATE TABLE #C (EmployeeID int PRIMARY KEY, OldPos int, OldUnit int, OldMgr int, Rk int, Family nvarchar(50), OldSal decimal(10,2),
                 RPromo float, RXfer float, RDest float, RSal float,
                 Ev varchar(40) NULL, NewPos int NULL, NewUnit int NULL, NewMgr int NULL, NewSal decimal(10,2) NULL);

-- ================================================================ job changes
INSERT #C (EmployeeID, OldPos, OldUnit, OldMgr, Rk, Family, OldSal, RPromo, RXfer, RDest, RSal)
SELECT e.EmployeeID, jo.PositionID, jo.OrganizationUnitID, jo.ManagerEmployeeID, p.JobLevelRank, p.JobFamily, c.BaseSalary,
       h.p1, h.p2, h.p3, h.p4
FROM dbo.Employees e
JOIN dbo.EmployeeJobHistory jo ON jo.EmployeeID = e.EmployeeID AND jo.EndDate IS NULL
JOIN dbo.Positions p ON p.PositionID = jo.PositionID
JOIN dbo.EmployeeCompensationHistory c ON c.EmployeeID = e.EmployeeID AND c.EndDate IS NULL
CROSS APPLY (SELECT p1 = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @QKey, '|', e.EmployeeID, '|promo')), 1, 4) AS int) & 2147483647) / 2147483648.0,
                    p2 = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @QKey, '|', e.EmployeeID, '|xfer')), 1, 4) AS int) & 2147483647) / 2147483648.0,
                    p3 = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @QKey, '|', e.EmployeeID, '|dest')), 1, 4) AS int) & 2147483647) / 2147483648.0,
                    p4 = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @QKey, '|', e.EmployeeID, '|sal')), 1, 4) AS int) & 2147483647) / 2147483648.0) h
WHERE p.JobLevelRank BETWEEN 6 AND 8
  AND e.HireDate <= DATEADD(MONTH, -6, @Date)
  AND NOT EXISTS (SELECT 1 FROM dbo.EmployeeJobHistory j WHERE j.EmployeeID = e.EmployeeID AND j.ChangeType <> 'Initial Assignment'
                  AND j.EffectiveDate > DATEADD(MONTH, -18, @Date));

-- promotions: one level up in the same department and job family
UPDATE c SET Ev = 'Promotion', NewPos = np.PositionID, NewUnit = c.OldUnit, NewMgr = c.OldMgr
FROM #C c
CROSS APPLY (SELECT TOP 1 p.PositionID FROM dbo.Positions p
             WHERE p.OrganizationUnitID = c.OldUnit AND p.JobLevelRank = c.Rk - 1 AND p.JobFamily = c.Family
             ORDER BY HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @QKey, '|', c.EmployeeID, '|pos', p.PositionID))) np
WHERE c.Rk IN (7, 8) AND c.RPromo < @pPromo;

-- transfers: same level, to a department below its target, under the smallest team of the same family
UPDATE c SET Ev = 'Department Transfer', NewPos = np.PositionID, NewUnit = d.UnitID, NewMgr = m.EmployeeID
FROM #C c
CROSS APPLY (SELECT TOP 1 w.OrganizationUnitID AS UnitID FROM dbo.DepartmentWorkforcePlan w
             WHERE w.OrganizationUnitID <> c.OldUnit
               AND (SELECT COUNT(*) FROM dbo.EmployeeJobHistory j2 WHERE j2.OrganizationUnitID = w.OrganizationUnitID AND j2.EndDate IS NULL)
                   < (SELECT TOP 1 h.TargetHeadcount FROM dbo.DepartmentWorkforcePlanHistory h WHERE h.OrganizationUnitID = w.OrganizationUnitID ORDER BY h.EffectiveDate DESC)
             ORDER BY HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @QKey, '|', c.EmployeeID, '|d', w.OrganizationUnitID))) d
CROSS APPLY (SELECT TOP 1 p.PositionID, p.JobFamily FROM dbo.Positions p
             WHERE p.OrganizationUnitID = d.UnitID AND p.JobLevelRank = c.Rk
             ORDER BY HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @QKey, '|', c.EmployeeID, '|tp', p.PositionID))) np
CROSS APPLY (SELECT TOP 1 jm.EmployeeID FROM #StaffMap sm
             JOIN dbo.Positions mp ON mp.PositionTitle = sm.MgrTitle AND mp.OrganizationUnitID = d.UnitID
             JOIN dbo.EmployeeJobHistory jm ON jm.PositionID = mp.PositionID AND jm.EndDate IS NULL
             WHERE sm.Family = np.JobFamily
             ORDER BY (SELECT COUNT(*) FROM dbo.EmployeeJobHistory r WHERE r.ManagerEmployeeID = jm.EmployeeID AND r.EndDate IS NULL),
                      HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @QKey, '|', c.EmployeeID, '|tm', jm.EmployeeID))) m
WHERE c.Ev IS NULL AND c.RXfer < @pXfer;

-- one transfer per destination department and quarter
;WITH t AS (SELECT EmployeeID, Ev, ROW_NUMBER() OVER (PARTITION BY NewUnit ORDER BY RDest, EmployeeID) AS rn FROM #C WHERE Ev = 'Department Transfer')
UPDATE c SET Ev = NULL, NewPos = NULL, NewUnit = NULL, NewMgr = NULL FROM #C c JOIN t ON t.EmployeeID = c.EmployeeID WHERE t.rn > 1;

-- new salary for each change: a multiple of 100 inside the ratio range and the new band; a change without room is dropped
UPDATE c SET NewSal = s.Lo + 100 * CAST(FLOOR(c.RSal * ((s.Hi - s.Lo) / 100 + 1)) AS int)
FROM #C c
JOIN dbo.Positions np ON np.PositionID = c.NewPos
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = c.NewUnit
JOIN #Band b ON b.JobLevel = np.JobLevel
JOIN #DF df ON df.UnitName = u.UnitName
CROSS APPLY (SELECT RLo = CASE c.Ev WHEN 'Promotion' THEN 1.06 ELSE 1.002 END, RHi = CASE c.Ev WHEN 'Promotion' THEN 1.12 ELSE 1.04 END) r
CROSS APPLY (SELECT BandLo = CAST(CEILING(b.Mn * df.F / 100.0) AS int) * 100, BandHi = CAST(FLOOR(b.Mx * df.F / 100.0) AS int) * 100,
                    RatioLo = CAST(CEILING(c.OldSal * r.RLo / 100.0) AS int) * 100, RatioHi = CAST(FLOOR(c.OldSal * r.RHi / 100.0) AS int) * 100,
                    Floor1 = CAST(c.OldSal AS int) + 100) x
CROSS APPLY (SELECT Lo = (SELECT MAX(v) FROM (VALUES (x.BandLo), (x.RatioLo), (x.Floor1)) t(v)),
                    Hi = (SELECT MIN(v) FROM (VALUES (x.BandHi), (x.RatioHi)) t(v))) s
WHERE c.Ev IS NOT NULL AND s.Lo <= s.Hi;
UPDATE #C SET Ev = NULL, NewPos = NULL, NewUnit = NULL, NewMgr = NULL WHERE Ev IS NOT NULL AND NewSal IS NULL;

-- write: fill the EndDate of the open rows, add the new open rows (the Employees rows are not touched)
UPDATE j SET EndDate = @Date FROM dbo.EmployeeJobHistory j JOIN #C c ON c.EmployeeID = j.EmployeeID AND j.EndDate IS NULL WHERE c.Ev IS NOT NULL;
INSERT dbo.EmployeeJobHistory (EmployeeID, EffectiveDate, EndDate, PositionID, OrganizationUnitID, ManagerEmployeeID, ChangeType, Reason)
SELECT c.EmployeeID, @Date, NULL, c.NewPos, c.NewUnit, c.NewMgr, c.Ev,
       CASE c.Ev WHEN 'Promotion' THEN N'Promoted to ' + p.PositionTitle
                 ELSE N'Transferred to ' + u.UnitName + N' as ' + p.PositionTitle END
FROM #C c JOIN dbo.Positions p ON p.PositionID = c.NewPos JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = c.NewUnit
WHERE c.Ev IS NOT NULL;
UPDATE k SET EndDate = @Date FROM dbo.EmployeeCompensationHistory k JOIN #C c ON c.EmployeeID = k.EmployeeID AND k.EndDate IS NULL WHERE c.Ev IS NOT NULL;
INSERT dbo.EmployeeCompensationHistory (EmployeeID, EffectiveDate, EndDate, BaseSalary, ChangeReason)
SELECT EmployeeID, @Date, NULL, NewSal, CASE Ev WHEN 'Promotion' THEN 'Promotion' ELSE 'Department Transfer' END FROM #C WHERE Ev IS NOT NULL;

-- ================================================================ annual increase (1 January) and market adjustment (April, July, October)
IF OBJECT_ID(N'tempdb..#P') IS NOT NULL DROP TABLE #P;
CREATE TABLE #P (EmployeeID int PRIMARY KEY, Reason varchar(40) NOT NULL, NewSal decimal(10,2) NOT NULL);

INSERT #P (EmployeeID, Reason, NewSal)
SELECT x.EmployeeID, x.Reason, s.Lo + 100 * CAST(FLOOR(x.RSal * ((s.Hi - s.Lo) / 100 + 1)) AS int)
FROM (
    SELECT e.EmployeeID, k.BaseSalary AS Sal, p.JobLevel, p.JobLevelRank, u.UnitName,
           CASE WHEN MONTH(@Date) = 1 THEN 'Annual Increase' ELSE 'Market Adjustment' END AS Reason,
           CASE WHEN MONTH(@Date) = 1 THEN 1.015 ELSE 1.04 END AS RLo, CASE WHEN MONTH(@Date) = 1 THEN 1.045 ELSE 1.08 END AS RHi,
           (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @QKey, '|', e.EmployeeID, '|pay')), 1, 4) AS int) & 2147483647) / 2147483648.0 AS RSal,
           (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|', @QKey, '|', e.EmployeeID, '|mkt')), 1, 4) AS int) & 2147483647) / 2147483648.0 AS RMkt
    FROM dbo.Employees e
    JOIN dbo.EmployeeJobHistory jo ON jo.EmployeeID = e.EmployeeID AND jo.EndDate IS NULL
    JOIN dbo.Positions p ON p.PositionID = jo.PositionID
    JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = jo.OrganizationUnitID
    JOIN dbo.EmployeeCompensationHistory k ON k.EmployeeID = e.EmployeeID AND k.EndDate IS NULL
    WHERE e.HireDate <= DATEADD(MONTH, -6, @Date)
      AND NOT EXISTS (SELECT 1 FROM dbo.EmployeeCompensationHistory k2 WHERE k2.EmployeeID = e.EmployeeID AND k2.EffectiveDate >= @Date)
) x
JOIN #Band b ON b.JobLevel = x.JobLevel
JOIN #DF df ON df.UnitName = x.UnitName
CROSS APPLY (SELECT BandHi = CAST(FLOOR(b.Mx * CASE WHEN x.JobLevelRank = 1 THEN 1.00 ELSE df.F END / 100.0) AS int) * 100) bd
CROSS APPLY (SELECT Lo = (SELECT MAX(v) FROM (VALUES (CAST(CEILING(x.Sal * x.RLo / 100.0) AS int) * 100), (CAST(x.Sal AS int) + 100)) t(v)),
                    Hi = (SELECT MIN(v) FROM (VALUES (CAST(FLOOR(x.Sal * x.RHi / 100.0) AS int) * 100), (bd.BandHi)) t(v))) s
WHERE s.Lo <= s.Hi
  AND ( (MONTH(@Date) = 1)
     OR (MONTH(@Date) IN (4, 7, 10) AND x.RMkt < @pMkt
         AND NOT EXISTS (SELECT 1 FROM dbo.EmployeeCompensationHistory k3 WHERE k3.EmployeeID = x.EmployeeID AND k3.ChangeReason = 'Market Adjustment')) );

UPDATE k SET EndDate = @Date FROM dbo.EmployeeCompensationHistory k JOIN #P p ON p.EmployeeID = k.EmployeeID AND k.EndDate IS NULL;
INSERT dbo.EmployeeCompensationHistory (EmployeeID, EffectiveDate, EndDate, BaseSalary, ChangeReason)
SELECT EmployeeID, @Date, NULL, NewSal, Reason FROM #P;

DROP TABLE #C, #P;
