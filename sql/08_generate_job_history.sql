-- 08_generate_job_history.sql: career history for all 151 employees, built BACKWARDS from the
-- current Employees row, so the open record (EndDate IS NULL) equals the current position, department and manager.
-- Deterministic: every random value is a hash of (seed, employee ID, label).
--
-- Scope (see PLAN.md, Generation rules / Job history):
--   * CEO, C-Level, VP and Director: one record each (hired into the position they hold).
--   * Manager, Senior, Professional, Junior: 0 to 5 events from this list:
--       Promotion (rank number -1), Department Transfer (same rank, other department),
--       Promotion + Department Transfer, Position Change (same rank and department), Manager Change.
--   * Events fall on 1 Jan / 1 Apr / 1 Jul / 1 Oct, >= 6 months after hire, <= 2026-07-01, >= 18 months apart.
--   * Every historical manager is a current employee, hired before the date, holding a management
--     position of higher rank in the same department on that date (taken from that manager's own history).
--   * Managers with reports keep all their events on or before their first report's hire date, so the
--     current manager was already in place when each report arrived.
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -f 65001 -i sql/08_generate_job_history.sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Seed       varchar(20) = 'DemoHR-2026';
DECLARE @LastEvent  date        = '2026-07-01';   -- last quarter start before 2026-10-01
-- Tunable event probabilities (Manager..Professional; about-targets from PLAN.md are reported in the checks)
-- (higher than the PLAN targets because recent hires and managers with reports cannot take every planned event)
DECLARE @pAnyPromo  float = 0.60;   -- at least one promotion (Manager, Senior, Professional)
DECLARE @pTwice     float = 0.60;   -- a second promotion, given a first (Manager, Senior)
DECLARE @pPT        float = 0.06;   -- a promotion that is also a department transfer
DECLARE @pXfer      float = 0.13;   -- a separate department transfer
DECLARE @pPos       float = 0.08;   -- a position change
DECLARE @pMgr       float = 0.20;   -- a separate manager change

BEGIN TRANSACTION;

-- ================================================================ working tables
CREATE TABLE #Q (Idx int PRIMARY KEY, D date NOT NULL);          -- quarter starts 2012-01-01 .. 2026-07-01
;WITH q AS (SELECT CAST('2012-01-01' AS date) AS D UNION ALL SELECT DATEADD(MONTH, 3, D) FROM q WHERE D < @LastEvent)
INSERT INTO #Q SELECT ROW_NUMBER() OVER (ORDER BY D), D FROM q OPTION (MAXRECURSION 0);

CREATE TABLE #X (EmployeeID int PRIMARY KEY, LvlRank int, UnitID int, PositionID int, ManagerID int NULL, HireDate date, Family nvarchar(50), MinReportHire date NULL);
INSERT INTO #X
SELECT e.EmployeeID, p.JobLevelRank, e.OrganizationUnitID, e.PositionID, e.ManagerEmployeeID, e.HireDate, p.JobFamily,
       (SELECT MIN(r.HireDate) FROM dbo.Employees r WHERE r.ManagerEmployeeID = e.EmployeeID)
FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID;

CREATE TABLE #HR (EmployeeID int, Label varchar(10), R float, PRIMARY KEY (EmployeeID, Label));
INSERT INTO #HR
SELECT x.EmployeeID, l.Label,
       (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|jh|', x.EmployeeID, '|', l.Label)), 1, 4) AS int) & 2147483647) / 2147483648.0
FROM #X x
CROSS JOIN (VALUES ('promo'),('twice'),('pt1'),('pt2'),('xfer'),('pc'),('mc'),('sh1'),('sh2'),('sh3'),('sh4'),('sh5'),
                   ('dt1'),('dt2'),('dt3'),('dt4'),('dt5')) l(Label);

CREATE TABLE #Seg (EmployeeID int, Seq int, Eff date, PositionID int, UnitID int, MgrID int NULL, ChangeType varchar(40), PRIMARY KEY (EmployeeID, Seq));
CREATE TABLE #L   (Type varchar(40), SortKey float);                                              -- planned events (unordered)
CREATE TABLE #Ev  (Seq int PRIMARY KEY, Type varchar(40), QIdx int NULL, Eff date NULL);          -- chosen events, chronological
CREATE TABLE #Tmp (Seq int PRIMARY KEY, Eff date, PositionID int, UnitID int, LvlRank int, ChangeType varchar(40), MgrID int NULL);

-- ================================================================ per-employee loop (ascending ID: managers come first)
DECLARE @X int = 1, @MaxX int = (SELECT MAX(EmployeeID) FROM #X);
DECLARE @R int, @D int, @P int, @M int, @H date, @Fam nvarchar(50), @MinRep date;
DECLARE @rPromo float, @rTwice float, @rPt1 float, @rPt2 float, @rXfer float, @rPc float, @rMc float,
        @rSh1 float, @rSh2 float, @rSh3 float, @rSh4 float, @rSh5 float;
DECLARE @nProm int, @n int, @qLo int, @qHi int, @cap int, @ok bit, @i int, @type varchar(40);
DECLARE @sp int, @sd int, @sr int, @pp int, @pu int, @pr int, @tgt int, @t date, @mgr int, @nextMgr int, @nextType varchar(40);
DECLARE @Fallbacks int = 0;

WHILE @X <= @MaxX
BEGIN
    SELECT @R = LvlRank, @D = UnitID, @P = PositionID, @M = ManagerID, @H = HireDate, @Fam = Family, @MinRep = MinReportHire
    FROM #X WHERE EmployeeID = @X;

    IF @R <= 4
    BEGIN   -- CEO, C-Level, VP, Director: hired into the position they hold
        INSERT INTO #Seg VALUES (@X, 0, @H, @P, @D, @M, 'Initial Assignment');
    END
    ELSE
    BEGIN
        SELECT @rPromo = MAX(CASE Label WHEN 'promo' THEN R END), @rTwice = MAX(CASE Label WHEN 'twice' THEN R END),
               @rPt1 = MAX(CASE Label WHEN 'pt1' THEN R END), @rPt2 = MAX(CASE Label WHEN 'pt2' THEN R END),
               @rXfer = MAX(CASE Label WHEN 'xfer' THEN R END), @rPc = MAX(CASE Label WHEN 'pc' THEN R END), @rMc = MAX(CASE Label WHEN 'mc' THEN R END),
               @rSh1 = MAX(CASE Label WHEN 'sh1' THEN R END), @rSh2 = MAX(CASE Label WHEN 'sh2' THEN R END), @rSh3 = MAX(CASE Label WHEN 'sh3' THEN R END),
               @rSh4 = MAX(CASE Label WHEN 'sh4' THEN R END), @rSh5 = MAX(CASE Label WHEN 'sh5' THEN R END)
        FROM #HR WHERE EmployeeID = @X;

        -- how many promotions (initial rank may be at most 2 below today's, and never below Junior = 8)
        SET @nProm = CASE WHEN @R BETWEEN 5 AND 7 AND @rPromo < @pAnyPromo
                          THEN CASE WHEN @R <= 6 AND @rTwice < @pTwice THEN 2 ELSE 1 END ELSE 0 END;

        DELETE FROM #L;
        IF @nProm >= 1 INSERT INTO #L VALUES (CASE WHEN @rPt1 < @pPT THEN 'Promotion + Department Transfer' ELSE 'Promotion' END, @rSh1);
        IF @nProm >= 2 INSERT INTO #L VALUES (CASE WHEN @rPt2 < @pPT THEN 'Promotion + Department Transfer' ELSE 'Promotion' END, @rSh2);
        IF @rXfer < @pXfer INSERT INTO #L VALUES ('Department Transfer', @rSh3);
        IF @rPc   < @pPos  INSERT INTO #L VALUES ('Position Change',     @rSh4);
        IF @rMc   < @pMgr  INSERT INTO #L VALUES ('Manager Change',      @rSh5);

        -- room for events: from 6 months after hire to the last quarter start (or the first report's hire date)
        SET @qLo = (SELECT MIN(Idx) FROM #Q WHERE D >= DATEADD(MONTH, 6, @H));
        SET @qHi = (SELECT MAX(Idx) FROM #Q WHERE D <= CASE WHEN @MinRep IS NOT NULL AND @MinRep < @LastEvent THEN @MinRep ELSE @LastEvent END);
        SET @cap = CASE WHEN @qLo IS NULL OR @qHi IS NULL OR @qHi < @qLo THEN 0 ELSE (@qHi - @qLo) / 6 + 1 END;   -- events are 6 quarters (18 months) apart
        SET @n = (SELECT COUNT(*) FROM #L);
        IF @n > @cap SET @n = @cap;

        SET @ok = 0;
        WHILE @n >= 0 AND @ok = 0
        BEGIN
            DELETE FROM #Ev; DELETE FROM #Tmp;
            INSERT INTO #Ev (Seq, Type) SELECT ROW_NUMBER() OVER (ORDER BY SortKey), Type FROM (SELECT TOP (@n) Type, SortKey FROM #L ORDER BY SortKey) t;

            IF @n > 0
            BEGIN   -- event dates: sorted random quarters, pushed apart by 6 quarters each
                ;WITH k AS (
                    SELECT v.i, kv = @qLo + CAST(FLOOR(h.R * ((@qHi - 6 * (@n - 1)) - @qLo + 1)) AS int)
                    FROM (VALUES (1),(2),(3),(4),(5)) v(i)
                    JOIN #HR h ON h.EmployeeID = @X AND h.Label = 'dt' + CAST(v.i AS varchar(2))
                    WHERE v.i <= @n
                ), s AS (SELECT kv, ROW_NUMBER() OVER (ORDER BY kv, i) AS rn FROM k)
                UPDATE ev SET QIdx = s.kv + 6 * (s.rn - 1) FROM #Ev ev JOIN s ON s.rn = ev.Seq;
                UPDATE ev SET Eff = q.D FROM #Ev ev JOIN #Q q ON q.Idx = ev.QIdx;
            END

            -- states, newest first: segment n is today's position; each event derives the segment before it
            INSERT INTO #Tmp (Seq, Eff, PositionID, UnitID, LvlRank, ChangeType)
            VALUES (@n, CASE WHEN @n = 0 THEN @H ELSE (SELECT Eff FROM #Ev WHERE Seq = @n) END, @P, @D, @R,
                    CASE WHEN @n = 0 THEN 'Initial Assignment' ELSE (SELECT Type FROM #Ev WHERE Seq = @n) END);
            SET @ok = 1; SET @i = @n; SET @sp = @P; SET @sd = @D; SET @sr = @R;
            WHILE @i >= 1 AND @ok = 1
            BEGIN
                SET @type = (SELECT Type FROM #Ev WHERE Seq = @i);
                SET @pp = NULL; SET @pu = @sd; SET @pr = @sr;
                IF @type IN ('Promotion', 'Promotion + Department Transfer') SET @pr = @sr + 1;
                IF @type IN ('Department Transfer', 'Promotion + Department Transfer')
                BEGIN   -- another department, picked by hash
                    SET @pu = NULL;
                    SELECT TOP 1 @pu = OrganizationUnitID FROM dbo.OrganizationUnits
                    WHERE UnitType = 'Department' AND OrganizationUnitID <> @sd
                    ORDER BY HASHBYTES('SHA2_256', CONCAT(@Seed, '|dept|', @X, '|', @i, '|', OrganizationUnitID));
                END
                IF @type = 'Manager Change' SET @pp = @sp;          -- same position, only the manager differs
                ELSE
                    SELECT TOP 1 @pp = PositionID FROM dbo.Positions
                    WHERE OrganizationUnitID = @pu AND JobLevelRank = @pr AND (@type <> 'Position Change' OR PositionID <> @sp)
                    ORDER BY CASE WHEN JobFamily = @Fam AND @type = 'Promotion' THEN 0 ELSE 1 END,
                             HASHBYTES('SHA2_256', CONCAT(@Seed, '|pos|', @X, '|', @i, '|', PositionID));
                IF @pp IS NULL OR @pu IS NULL SET @ok = 0;
                ELSE
                BEGIN
                    INSERT INTO #Tmp (Seq, Eff, PositionID, UnitID, LvlRank, ChangeType)
                    VALUES (@i - 1, CASE WHEN @i - 1 = 0 THEN @H ELSE (SELECT Eff FROM #Ev WHERE Seq = @i - 1) END, @pp, @pu, @pr,
                            CASE WHEN @i - 1 = 0 THEN 'Initial Assignment' ELSE (SELECT Type FROM #Ev WHERE Seq = @i - 1) END);
                    SET @sp = @pp; SET @sd = @pu; SET @sr = @pr; SET @i -= 1;
                END
            END

            -- managers: today's manager for the open record, then eligible managers going back in time
            IF @ok = 1
            BEGIN
                SET @t = (SELECT Eff FROM #Tmp WHERE Seq = @n);
                IF EXISTS (SELECT 1 FROM #Seg s JOIN dbo.Positions pm ON pm.PositionID = s.PositionID JOIN #X xm ON xm.EmployeeID = s.EmployeeID
                           WHERE s.EmployeeID = @M AND s.Eff <= @t
                             AND NOT EXISTS (SELECT 1 FROM #Seg s2 WHERE s2.EmployeeID = s.EmployeeID AND s2.Eff > s.Eff AND s2.Eff <= @t)
                             AND s.UnitID = @D AND pm.IsManagementPosition = 1 AND pm.JobLevelRank < @R AND xm.HireDate < @t)
                    UPDATE #Tmp SET MgrID = @M WHERE Seq = @n;
                ELSE SET @ok = 0;
            END
            SET @i = @n - 1;
            WHILE @i >= 0 AND @ok = 1
            BEGIN
                SELECT @t = Eff, @sd = UnitID, @sr = LvlRank FROM #Tmp WHERE Seq = @i;
                SELECT @nextMgr = MgrID, @nextType = ChangeType FROM #Tmp WHERE Seq = @i + 1;
                SET @tgt = CASE WHEN @sr >= 6 THEN 5 ELSE 4 END;     -- staff report to a Manager, Managers to a Director
                SET @mgr = NULL;
                SELECT TOP 1 @mgr = s.EmployeeID
                FROM #Seg s JOIN dbo.Positions pm ON pm.PositionID = s.PositionID JOIN #X xm ON xm.EmployeeID = s.EmployeeID
                WHERE s.EmployeeID <> @X AND s.Eff <= @t
                  AND NOT EXISTS (SELECT 1 FROM #Seg s2 WHERE s2.EmployeeID = s.EmployeeID AND s2.Eff > s.Eff AND s2.Eff <= @t)
                  AND s.UnitID = @sd AND pm.IsManagementPosition = 1 AND pm.JobLevelRank < @sr AND xm.HireDate < @t
                  AND (@nextType <> 'Manager Change' OR s.EmployeeID <> @nextMgr)
                ORDER BY ABS(pm.JobLevelRank - @tgt), CASE WHEN s.EmployeeID = @nextMgr THEN 0 ELSE 1 END,
                         HASHBYTES('SHA2_256', CONCAT(@Seed, '|mgr|', @X, '|', @i, '|', s.EmployeeID));
                IF @mgr IS NULL SET @ok = 0;
                ELSE BEGIN UPDATE #Tmp SET MgrID = @mgr WHERE Seq = @i; SET @i -= 1; END
            END

            IF @ok = 1
                INSERT INTO #Seg SELECT @X, Seq, Eff, PositionID, UnitID, MgrID, ChangeType FROM #Tmp;
            ELSE
                SET @n -= 1;     -- not feasible: try again with one event fewer
        END

        IF @ok = 0
        BEGIN   -- should not happen: keep one record that matches today's row and let the checks show it
            INSERT INTO #Seg VALUES (@X, 0, @H, @P, @D, @M, 'Initial Assignment');
            SET @Fallbacks += 1;
        END
    END
    SET @X += 1;
END

-- ================================================================ write to EmployeeJobHistory (clears only this table)
DELETE FROM dbo.EmployeeJobHistory;
DECLARE @seedJh int = CASE WHEN EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.EmployeeJobHistory') AND last_value IS NULL) THEN 1 ELSE 0 END;
DBCC CHECKIDENT ('dbo.EmployeeJobHistory', RESEED, @seedJh) WITH NO_INFOMSGS;

INSERT INTO dbo.EmployeeJobHistory (EmployeeID, EffectiveDate, EndDate, PositionID, OrganizationUnitID, ManagerEmployeeID, ChangeType, Reason)
SELECT s.EmployeeID, s.Eff,
       LEAD(s.Eff) OVER (PARTITION BY s.EmployeeID ORDER BY s.Seq),
       s.PositionID, s.UnitID, s.MgrID, s.ChangeType,
       CASE s.ChangeType
            WHEN 'Initial Assignment'                THEN N'Hired as ' + p.PositionTitle
            WHEN 'Promotion'                         THEN N'Promoted to ' + p.PositionTitle
            WHEN 'Department Transfer'               THEN N'Transferred to ' + u.UnitName + N' as ' + p.PositionTitle
            WHEN 'Promotion + Department Transfer'   THEN N'Promoted to ' + p.PositionTitle + N' in ' + u.UnitName
            WHEN 'Position Change'                   THEN N'Moved to ' + p.PositionTitle
            WHEN 'Manager Change'                    THEN N'Reporting line changed'
       END
FROM #Seg s
JOIN dbo.Positions p ON p.PositionID = s.PositionID
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = s.UnitID
ORDER BY s.EmployeeID, s.Seq;

COMMIT TRANSACTION;

IF @Fallbacks > 0 PRINT CONCAT('WARNING: ', @Fallbacks, ' employee(s) fell back to a single record.');

DROP TABLE #Q, #X, #HR, #Seg, #L, #Ev, #Tmp;
GO

-- ================================================================ checks
SET NOCOUNT ON;
PRINT '--- 1. Records and open records';
SELECT COUNT(*) AS Records, COUNT(DISTINCT EmployeeID) AS EmployeesWithHistory,
       SUM(CASE WHEN EndDate IS NULL THEN 1 ELSE 0 END) AS OpenRecords,
       (SELECT COUNT(*) FROM (SELECT EmployeeID FROM dbo.EmployeeJobHistory WHERE EndDate IS NULL GROUP BY EmployeeID HAVING COUNT(*) <> 1) z) AS EmployeesNotExactlyOneOpen
FROM dbo.EmployeeJobHistory;

PRINT '--- 2. Open record equals the Employees row: position, department, manager (mismatches, expect 0)';
SELECT COUNT(*) AS Employees,
       SUM(CASE WHEN h.PositionID = e.PositionID AND h.OrganizationUnitID = e.OrganizationUnitID
                 AND ISNULL(h.ManagerEmployeeID, -1) = ISNULL(e.ManagerEmployeeID, -1) THEN 1 ELSE 0 END) AS OpenRecordMatches,
       SUM(CASE WHEN h.EmployeeID IS NULL OR h.PositionID <> e.PositionID OR h.OrganizationUnitID <> e.OrganizationUnitID
                 OR ISNULL(h.ManagerEmployeeID, -1) <> ISNULL(e.ManagerEmployeeID, -1) THEN 1 ELSE 0 END) AS Mismatches
FROM dbo.Employees e LEFT JOIN dbo.EmployeeJobHistory h ON h.EmployeeID = e.EmployeeID AND h.EndDate IS NULL;

PRINT '--- 3. Periods: first record starts on the hire date; no gaps or overlaps (violations, expect 0)';
;WITH j AS (
    SELECT h.*, ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate) AS rn,
           LEAD(EffectiveDate) OVER (PARTITION BY EmployeeID ORDER BY EffectiveDate) AS NextEff
    FROM dbo.EmployeeJobHistory h)
SELECT (SELECT COUNT(*) FROM j JOIN dbo.Employees e ON e.EmployeeID = j.EmployeeID WHERE j.rn = 1 AND (j.EffectiveDate <> e.HireDate OR j.ChangeType <> 'Initial Assignment')) AS FirstRecordWrong,
       (SELECT COUNT(*) FROM j WHERE rn > 1 AND ChangeType = 'Initial Assignment') AS ExtraInitialRecords,
       (SELECT COUNT(*) FROM j WHERE NextEff IS NOT NULL AND ISNULL(EndDate, '9999-12-31') <> NextEff) AS GapsOrOverlaps,
       (SELECT COUNT(*) FROM j WHERE NextEff IS NULL AND EndDate IS NOT NULL) AS LastRecordClosed;

PRINT '--- 4. Event rules (violations, expect 0)';
;WITH j AS (
    SELECT h.*, p.JobLevelRank AS Rnk, p.OrganizationUnitID AS PosUnit,
           LAG(h.PositionID) OVER (PARTITION BY h.EmployeeID ORDER BY h.EffectiveDate) AS PrevPos,
           LAG(h.OrganizationUnitID) OVER (PARTITION BY h.EmployeeID ORDER BY h.EffectiveDate) AS PrevUnit,
           LAG(h.ManagerEmployeeID) OVER (PARTITION BY h.EmployeeID ORDER BY h.EffectiveDate) AS PrevMgr,
           LAG(h.EffectiveDate) OVER (PARTITION BY h.EmployeeID ORDER BY h.EffectiveDate) AS PrevEff,
           LAG(h.ChangeType) OVER (PARTITION BY h.EmployeeID ORDER BY h.EffectiveDate) AS PrevChange
    FROM dbo.EmployeeJobHistory h JOIN dbo.Positions p ON p.PositionID = h.PositionID
), k AS (
    SELECT j.*, pp.JobLevelRank AS PrevRnk FROM j LEFT JOIN dbo.Positions pp ON pp.PositionID = j.PrevPos
)
SELECT (SELECT COUNT(*) FROM k WHERE OrganizationUnitID <> PosUnit) AS UnitNotPositionUnit,
       (SELECT COUNT(*) FROM k WHERE ChangeType <> 'Initial Assignment' AND (DAY(EffectiveDate) <> 1 OR MONTH(EffectiveDate) NOT IN (1,4,7,10))) AS NotQuarterStart,
       (SELECT COUNT(*) FROM k JOIN dbo.Employees e ON e.EmployeeID = k.EmployeeID WHERE k.ChangeType <> 'Initial Assignment' AND k.EffectiveDate < DATEADD(MONTH, 6, e.HireDate)) AS Under6MonthsAfterHire,
       (SELECT COUNT(*) FROM k WHERE ChangeType <> 'Initial Assignment' AND EffectiveDate >= '2026-10-01') AS OnOrAfter20261001,
       (SELECT COUNT(*) FROM k WHERE PrevEff IS NOT NULL AND PrevChange <> 'Initial Assignment' AND EffectiveDate < DATEADD(MONTH, 18, PrevEff)) AS Under18MonthsBetweenEvents,
       (SELECT COUNT(*) FROM k WHERE ChangeType = 'Promotion' AND NOT (PrevRnk - Rnk = 1 AND PrevUnit = OrganizationUnitID)) AS BadPromotion,
       (SELECT COUNT(*) FROM k WHERE ChangeType = 'Department Transfer' AND NOT (PrevRnk = Rnk AND PrevUnit <> OrganizationUnitID)) AS BadTransfer,
       (SELECT COUNT(*) FROM k WHERE ChangeType = 'Promotion + Department Transfer' AND NOT (PrevRnk - Rnk = 1 AND PrevUnit <> OrganizationUnitID)) AS BadPromoTransfer,
       (SELECT COUNT(*) FROM k WHERE ChangeType = 'Position Change' AND NOT (PrevRnk = Rnk AND PrevUnit = OrganizationUnitID AND PrevPos <> PositionID)) AS BadPositionChange,
       (SELECT COUNT(*) FROM k WHERE ChangeType = 'Manager Change' AND NOT (PrevPos = PositionID AND PrevUnit = OrganizationUnitID AND ISNULL(PrevMgr, -1) <> ISNULL(ManagerEmployeeID, -1))) AS BadManagerChange;

PRINT '--- 5. Starting rank: today''s rank or up to 2 ranks lower (violations, expect 0); CEO 1 record; C-Level at most 2';
SELECT (SELECT COUNT(*) FROM dbo.EmployeeJobHistory f JOIN dbo.Positions pf ON pf.PositionID = f.PositionID
        JOIN dbo.Employees e ON e.EmployeeID = f.EmployeeID JOIN dbo.Positions pc ON pc.PositionID = e.PositionID
        WHERE f.ChangeType = 'Initial Assignment' AND (pf.JobLevelRank - pc.JobLevelRank NOT BETWEEN 0 AND 2)) AS StartRankOutOfRange,
       (SELECT MAX(c) FROM (SELECT COUNT(*) AS c FROM dbo.EmployeeJobHistory h JOIN dbo.Positions p ON p.PositionID = h.PositionID WHERE p.JobLevelRank = 1 GROUP BY h.EmployeeID) z) AS CeoRecords,
       (SELECT MAX(c) FROM (SELECT COUNT(*) AS c FROM dbo.EmployeeJobHistory h JOIN dbo.Employees e ON e.EmployeeID = h.EmployeeID JOIN dbo.Positions p ON p.PositionID = e.PositionID WHERE p.JobLevelRank = 2 GROUP BY h.EmployeeID) z) AS MaxCLevelRecords;

PRINT '--- 6. Historical managers: current employee, hired before the date, higher-ranked management position in the same department on that date (violations, expect 0)';
;WITH f AS (
    SELECT h.EmployeeID, h.ManagerEmployeeID,
           CASE WHEN EXISTS (
                SELECT 1 FROM dbo.EmployeeJobHistory m
                JOIN dbo.Positions pm ON pm.PositionID = m.PositionID
                JOIN dbo.Employees em ON em.EmployeeID = m.EmployeeID
                JOIN dbo.Positions ph ON ph.PositionID = h.PositionID
                WHERE m.EmployeeID = h.ManagerEmployeeID AND m.EffectiveDate <= h.EffectiveDate AND (m.EndDate IS NULL OR m.EndDate > h.EffectiveDate)
                  AND em.HireDate < h.EffectiveDate AND pm.IsManagementPosition = 1 AND pm.JobLevelRank < ph.JobLevelRank
                  AND (m.OrganizationUnitID = h.OrganizationUnitID OR pm.JobLevelRank = 1))
                THEN 0 ELSE 1 END AS NotEligible
    FROM dbo.EmployeeJobHistory h WHERE h.ManagerEmployeeID IS NOT NULL)
SELECT COUNT(*) AS RecordsWithManager, SUM(NotEligible) AS ManagerNotEligible,
       SUM(CASE WHEN ManagerEmployeeID = EmployeeID THEN 1 ELSE 0 END) AS SelfManaged
FROM f;

PRINT '--- 7. Records per employee';
SELECT Records, COUNT(*) AS Employees FROM (SELECT EmployeeID, COUNT(*) AS Records FROM dbo.EmployeeJobHistory GROUP BY EmployeeID) z GROUP BY Records ORDER BY Records;

PRINT '--- 8. Event mix among the 132 employees below Director (PLAN targets: 1 promotion ~30%, 2 ~8%, transfer ~10%, promotion + transfer ~4%, position change ~5%, manager change ~12%)';
;WITH b AS (
    SELECT e.EmployeeID FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID WHERE p.JobLevelRank >= 5),
c AS (
    SELECT b.EmployeeID,
           SUM(CASE WHEN h.ChangeType IN ('Promotion','Promotion + Department Transfer') THEN 1 ELSE 0 END) AS Promos,
           SUM(CASE WHEN h.ChangeType = 'Department Transfer' THEN 1 ELSE 0 END) AS Transfers,
           SUM(CASE WHEN h.ChangeType = 'Promotion + Department Transfer' THEN 1 ELSE 0 END) AS PromoTransfers,
           SUM(CASE WHEN h.ChangeType = 'Position Change' THEN 1 ELSE 0 END) AS PosChanges,
           SUM(CASE WHEN h.ChangeType = 'Manager Change' THEN 1 ELSE 0 END) AS MgrChanges
    FROM b LEFT JOIN dbo.EmployeeJobHistory h ON h.EmployeeID = b.EmployeeID GROUP BY b.EmployeeID)
SELECT COUNT(*) AS N,
       SUM(CASE WHEN Promos = 1 THEN 1 ELSE 0 END) AS OnePromotion,   CAST(100.0 * SUM(CASE WHEN Promos = 1 THEN 1 ELSE 0 END) / COUNT(*) AS decimal(4,1)) AS PctOne,
       SUM(CASE WHEN Promos = 2 THEN 1 ELSE 0 END) AS TwoPromotions,  CAST(100.0 * SUM(CASE WHEN Promos = 2 THEN 1 ELSE 0 END) / COUNT(*) AS decimal(4,1)) AS PctTwo,
       SUM(CASE WHEN Transfers > 0 THEN 1 ELSE 0 END) AS WithTransfer,           CAST(100.0 * SUM(CASE WHEN Transfers > 0 THEN 1 ELSE 0 END) / COUNT(*) AS decimal(4,1)) AS PctTransfer,
       SUM(CASE WHEN PromoTransfers > 0 THEN 1 ELSE 0 END) AS WithPromoTransfer, CAST(100.0 * SUM(CASE WHEN PromoTransfers > 0 THEN 1 ELSE 0 END) / COUNT(*) AS decimal(4,1)) AS PctPromoTransfer,
       SUM(CASE WHEN PosChanges > 0 THEN 1 ELSE 0 END) AS WithPositionChange,    CAST(100.0 * SUM(CASE WHEN PosChanges > 0 THEN 1 ELSE 0 END) / COUNT(*) AS decimal(4,1)) AS PctPosChange,
       SUM(CASE WHEN MgrChanges > 0 THEN 1 ELSE 0 END) AS WithManagerChange,     CAST(100.0 * SUM(CASE WHEN MgrChanges > 0 THEN 1 ELSE 0 END) / COUNT(*) AS decimal(4,1)) AS PctMgrChange
FROM c;

PRINT '--- 9. Events by year and type';
SELECT YEAR(EffectiveDate) AS Yr, SUM(CASE WHEN ChangeType IN ('Promotion','Promotion + Department Transfer') THEN 1 ELSE 0 END) AS Promotions,
       SUM(CASE WHEN ChangeType IN ('Department Transfer','Promotion + Department Transfer') THEN 1 ELSE 0 END) AS Transfers,
       SUM(CASE WHEN ChangeType = 'Position Change' THEN 1 ELSE 0 END) AS PositionChanges,
       SUM(CASE WHEN ChangeType = 'Manager Change' THEN 1 ELSE 0 END) AS ManagerChanges
FROM dbo.EmployeeJobHistory WHERE ChangeType <> 'Initial Assignment' GROUP BY YEAR(EffectiveDate) ORDER BY Yr;
GO
