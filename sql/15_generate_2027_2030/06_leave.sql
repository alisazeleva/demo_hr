-- 06_leave.sql: leave records after the first load (step 7 of sql/15_generate_2027_2030.sql)
-- The first load has leave up to 2027-03-31. This step adds leave from 2027-04-01 on, with the rules of 11_generate_leave.sql:
--   Vacation       22-28 working days a year in 2-4 blocks: one summer block of 10-15 days between 1 June and 15 August, the other blocks
--                  in Jan-May, 16 Aug-Oct and Nov-Dec. Partial years (hired during the year) are scaled. In 2027 the winter blocks of the
--                  first load count (their days are taken off the year's total) and new blocks start on 1 April or later.
--   Sick Leave     0-5 episodes a year (average 2.5) of 1-5 working days; for 2026 only the days after 2026-11-16, where the first load stops.      Parental Leave  1.2% of employees a year, 30-120 working days.
--   Unpaid Leave   0.7% a year, 5-20 working days.      Bereavement  1% a year, 1-3 working days.
--   Placement      long and rare leave first, then vacation blocks, then sick episodes; an item that cannot be placed without touching
--                  another leave of the same employee is dropped. Leave of the first load is never moved or changed.
-- Requests: a vacation, unpaid or parental request is made 14-150 days before it starts (never before the hire date); sick leave and
--   bereavement are reported on the first day. A request is decided at once (0-3 days), or for 20% of vacation, unpaid and parental
--   requests 14 days before the start (Pending until then). 3% of vacation and unpaid requests end Rejected. The stored Status is the final
--   one (Approved or Rejected, with the approver = the employee's manager on the request date, the CHRO for the CEO). dbo.LeaveRequestInfo
--   holds the request date, the decision date, the final status and the approver; Power BI shows a leave from its request date, as Pending
--   until its decision date. The Pending requests of the first load get an info row too (request date 2026-11-16, decision date the later of
--   start - 14 days and 2026-11-17, Approved 97% / Rejected 3%); their EmployeeLeaves rows are not changed.
-- The whole plan of an employee and year comes from hashes and the first-load leave only, so it does not depend on how often the update runs:
-- a leave is added when its request date falls in the period. Runs inside the transaction opened by 01_start.sql. Only inserts.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Seed     varchar(30) = 'demohr-update-v1';
DECLARE @Old date = (SELECT OldDate FROM #Run), @New date = (SELECT NewDate FROM #Run);
DECLARE @BaseEnd  date = '2027-03-31';                  -- last day with leave in the first load
DECLARE @Y1 int = CASE WHEN YEAR(@Old) < 2027 THEN 2026 ELSE YEAR(@Old) END,   -- 2026: only sick leave for 17 Nov - 31 Dec
          @Y2 int = YEAR(@New) + 1;
DECLARE @pParental float = 0.012, @pUnpaid float = 0.007, @pBereave float = 0.010, @pRejected float = 0.03, @pSlow float = 0.20;
DECLARE @Chro int = (SELECT TOP 1 j.EmployeeID FROM dbo.EmployeeJobHistory j JOIN dbo.Positions p ON p.PositionID = j.PositionID
                     WHERE p.PositionTitle = N'Chief Human Resources Officer' AND j.EndDate IS NULL);

-- ================================================================ working-day calendar
CREATE TABLE #WD (Seq int PRIMARY KEY, D date NOT NULL UNIQUE, Y int NOT NULL);
;WITH d AS (SELECT DATEFROMPARTS(@Y1, 1, 1) AS D UNION ALL SELECT DATEADD(DAY, 1, D) FROM d WHERE D < DATEFROMPARTS(@Y2, 12, 31))
INSERT INTO #WD (Seq, D, Y)
SELECT ROW_NUMBER() OVER (ORDER BY D), D, YEAR(D) FROM d
WHERE DATEDIFF(DAY, '19000101', D) % 7 < 5
  AND NOT EXISTS (SELECT 1 FROM dbo.PublicHolidays h WHERE h.HolidayDate = d.D)
OPTION (MAXRECURSION 0);
DECLARE @N int = (SELECT MAX(Seq) FROM #WD);

CREATE TABLE #Yr  (Y int PRIMARY KEY, FirstSeq int, LastSeq int);
INSERT INTO #Yr SELECT Y, MIN(Seq), MAX(Seq) FROM #WD GROUP BY Y;
CREATE TABLE #Win (Y int, W char(1), Lo int, Hi int, PRIMARY KEY (Y, W));      -- A Jan-May, S 1 Jun-15 Aug, B 16 Aug-Oct, C Nov-Dec
INSERT INTO #Win
SELECT y.Y, w.W,
       (SELECT MIN(Seq) FROM #WD WHERE D >= CASE WHEN DATEFROMPARTS(y.Y, w.M1, w.D1) > @BaseEnd THEN DATEFROMPARTS(y.Y, w.M1, w.D1) ELSE DATEADD(DAY, 1, @BaseEnd) END),
       (SELECT MAX(Seq) FROM #WD WHERE D <= DATEFROMPARTS(y.Y, w.M2, w.D2))
FROM #Yr y CROSS JOIN (VALUES ('A',1,1,5,31),('S',6,1,8,15),('B',8,16,10,31),('C',11,1,12,31)) w(W, M1, D1, M2, D2);

-- leave of the first load (and its Pending requests) as obstacles, in working-day numbers
CREATE TABLE #Obs (EmployeeID int, S int, E int, Vac int, Y int);
INSERT INTO #Obs
SELECT l.EmployeeID, a.Seq, b.Seq, CASE WHEN t.LeaveTypeName = N'Vacation' AND l.Status <> 'Rejected' THEN b.Seq - a.Seq + 1 ELSE 0 END, YEAR(l.StartDate)
FROM dbo.EmployeeLeaves l
JOIN dbo.LeaveTypes t ON t.LeaveTypeID = l.LeaveTypeID
JOIN #WD a ON a.D = l.StartDate JOIN #WD b ON b.D = l.EndDate
WHERE NOT EXISTS (SELECT 1 FROM dbo.LeaveRequestInfo i WHERE i.LeaveID = l.LeaveID AND i.IsNew = 1);

-- ================================================================ employee-year plans
CREATE TABLE #Emp (EmployeeID int PRIMARY KEY, HireDate date, HireSeq int);
INSERT INTO #Emp
SELECT e.EmployeeID, e.HireDate, ISNULL((SELECT MIN(Seq) FROM #WD WHERE D >= e.HireDate), @N + 1)
FROM dbo.Employees e WHERE e.HireDate <= DATEFROMPARTS(@Y2, 12, 31);

CREATE TABLE #EY (EmployeeID int, Y int, StartSeq int, EndSeq int, YLen int, Frac float,
                  rvt float, rvn float, rvs float, rp1 float, rp2 float, rwa float, rwb float, rwc float, rse float, rse2 float,
                  rpar float, rparl float, runp float, runpl float, rber float, rberl float,
                  T int NULL, N0 int NULL, HasSum bit NULL, S int NULL, NOther int NULL, R int NULL, P1 int NULL, P2 int NULL, P3 int NULL,
                  W1 char(1) NULL, W2 char(1) NULL, W3 char(1) NULL, NSick int NULL,
                  PRIMARY KEY (EmployeeID, Y));
INSERT INTO #EY (EmployeeID, Y, StartSeq, EndSeq, YLen, Frac, rvt, rvn, rvs, rp1, rp2, rwa, rwb, rwc, rse, rse2, rpar, rparl, runp, runpl, rber, rberl)
SELECT x.EmployeeID, y.Y, s.StartSeq, y.LastSeq, y.LastSeq - y.FirstSeq + 1,
       (y.LastSeq - s.StartSeq + 1.0) / (y.LastSeq - y.FirstSeq + 1),
       r.vt, r.vn, r.vs, r.p1, r.p2, r.wa, r.wb, r.wc, r.se, r.se2, r.par, r.parl, r.unp, r.unpl, r.ber, r.berl
FROM #Emp x
JOIN #Yr y ON 1 = 1
CROSS APPLY (SELECT StartSeq = (SELECT MAX(v) FROM (VALUES (x.HireSeq), (y.FirstSeq), (CASE WHEN y.Y = 2026 THEN (SELECT MIN(Seq) FROM #WD WHERE D > '2026-11-16') END)) t(v))) s
CROSS APPLY (SELECT
    vt   = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|vt')),   1, 4) AS int) & 2147483647) / 2147483648.0,
    vn   = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|vn')),   1, 4) AS int) & 2147483647) / 2147483648.0,
    vs   = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|vs')),   1, 4) AS int) & 2147483647) / 2147483648.0,
    p1   = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|p1')),   1, 4) AS int) & 2147483647) / 2147483648.0,
    p2   = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|p2')),   1, 4) AS int) & 2147483647) / 2147483648.0,
    wa   = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|wa')),   1, 4) AS int) & 2147483647) / 2147483648.0,
    wb   = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|wb')),   1, 4) AS int) & 2147483647) / 2147483648.0,
    wc   = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|wc')),   1, 4) AS int) & 2147483647) / 2147483648.0,
    se   = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|se')),   1, 4) AS int) & 2147483647) / 2147483648.0,
    se2  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|se2')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    par  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|par')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    parl = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|parl')), 1, 4) AS int) & 2147483647) / 2147483648.0,
    unp  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|unp')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    unpl = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|unpl')), 1, 4) AS int) & 2147483647) / 2147483648.0,
    ber  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|ber')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    berl = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|berl')), 1, 4) AS int) & 2147483647) / 2147483648.0) r
WHERE s.StartSeq <= y.LastSeq;

-- vacation total (22-28, scaled for part-years, less the vacation already in the first load), number of blocks, summer block
UPDATE #EY SET T  = CASE WHEN Frac >= 0.999 THEN 22 + CAST(FLOOR(rvt * 7) AS int) ELSE CAST(ROUND((22 + FLOOR(rvt * 7)) * Frac, 0) AS int) END,
               N0 = 2 + CAST(FLOOR(rvn * 3) AS int);
UPDATE #EY SET T = 0 WHERE Y = 2026;                                  -- 2026 has only the last weeks: sick leave only
UPDATE e SET T = CASE WHEN e.T - o.Days < 0 THEN 0 ELSE e.T - o.Days END
FROM #EY e JOIN (SELECT EmployeeID, SUM(Vac) AS Days FROM #Obs WHERE Y = 2027 GROUP BY EmployeeID) o ON o.EmployeeID = e.EmployeeID
WHERE e.Y = 2027;
UPDATE e SET HasSum = CASE WHEN e.T >= 14 AND e.StartSeq <= w.Lo THEN 1 ELSE 0 END
FROM #EY e JOIN #Win w ON w.Y = e.Y AND w.W = 'S';
UPDATE #EY SET S = CASE WHEN HasSum = 1 THEN CASE WHEN 10 + CAST(FLOOR(rvs * 6) AS int) > T - 4 THEN T - 4 ELSE 10 + CAST(FLOOR(rvs * 6) AS int) END END;
UPDATE #EY SET HasSum = 0, S = NULL WHERE HasSum = 1 AND S < 5;
UPDATE #EY SET R = T - ISNULL(S, 0);
UPDATE #EY SET NOther = CASE WHEN R < 2 THEN 0
                             ELSE (SELECT MIN(v) FROM (VALUES (CASE WHEN HasSum = 1 THEN N0 - 1 ELSE N0 END), (3), (R / 2)) t(v)) END;
UPDATE #EY SET P1 = CASE NOther WHEN 1 THEN R WHEN 2 THEN 2 + CAST(FLOOR(rp1 * (R - 4 + 1)) AS int) WHEN 3 THEN 2 + CAST(FLOOR(rp1 * (R - 6 + 1)) AS int) END WHERE NOther >= 1;
UPDATE #EY SET P2 = CASE NOther WHEN 2 THEN R - P1 WHEN 3 THEN 2 + CAST(FLOOR(rp2 * ((R - P1) - 4 + 1)) AS int) END WHERE NOther >= 2;
UPDATE #EY SET P3 = R - P1 - P2 WHERE NOther = 3;
UPDATE #EY SET W1 = CASE WHEN (CASE WHEN rwb < rwa THEN 1 ELSE 0 END + CASE WHEN rwc < rwa THEN 1 ELSE 0 END) = 0 THEN 'A'
                         WHEN (CASE WHEN rwa <= rwb THEN 1 ELSE 0 END + CASE WHEN rwc < rwb THEN 1 ELSE 0 END) = 0 THEN 'B' ELSE 'C' END,
               W3 = CASE WHEN (CASE WHEN rwb < rwa THEN 1 ELSE 0 END + CASE WHEN rwc < rwa THEN 1 ELSE 0 END) = 2 THEN 'A'
                         WHEN (CASE WHEN rwa <= rwb THEN 1 ELSE 0 END + CASE WHEN rwc < rwb THEN 1 ELSE 0 END) = 2 THEN 'B' ELSE 'C' END;
UPDATE #EY SET W2 = CASE WHEN 'A' NOT IN (W1, W3) THEN 'A' WHEN 'B' NOT IN (W1, W3) THEN 'B' ELSE 'C' END;
-- sick episodes: 0-5 a year (even spread by hash, scaled by the share of the year that is employed)
UPDATE #EY SET NSick = CASE WHEN FLOOR(FLOOR(6 * rse) * Frac + rse2) > 5 THEN 5 ELSE CAST(FLOOR(FLOOR(6 * rse) * Frac + rse2) AS int) END;

-- ================================================================ items to place
CREATE TABLE #Item (EmployeeID int, Y int, TypeName varchar(30), Kind varchar(20), Len int, Lo int, Hi int, Prio int, K int, Seq int NULL, S int NULL);

INSERT INTO #Item (EmployeeID, Y, TypeName, Kind, Len, Lo, Hi, Prio, K)   -- parental, unpaid, bereavement
SELECT EmployeeID, Y, 'Parental Leave', 'Parental', 30 + CAST(FLOOR(rparl * 91) AS int), StartSeq, EndSeq, 1, 1 FROM #EY WHERE rpar < @pParental AND Y >= 2027
UNION ALL
SELECT EmployeeID, Y, 'Unpaid Leave', 'Unpaid', 5 + CAST(FLOOR(runpl * 16) AS int), StartSeq, EndSeq, 2, 1 FROM #EY WHERE runp < @pUnpaid AND Y >= 2027
UNION ALL
SELECT EmployeeID, Y, 'Bereavement', 'Bereavement', 1 + CAST(FLOOR(rberl * 3) AS int), StartSeq, EndSeq, 3, 1 FROM #EY WHERE rber < @pBereave AND Y >= 2027;

INSERT INTO #Item (EmployeeID, Y, TypeName, Kind, Len, Lo, Hi, Prio, K)   -- summer block
SELECT e.EmployeeID, e.Y, 'Vacation', 'Summer', e.S, CASE WHEN e.StartSeq > w.Lo THEN e.StartSeq ELSE w.Lo END, w.Hi, 4, 0
FROM #EY e JOIN #Win w ON w.Y = e.Y AND w.W = 'S' WHERE e.HasSum = 1;

INSERT INTO #Item (EmployeeID, Y, TypeName, Kind, Len, Lo, Hi, Prio, K)   -- the other vacation blocks (1 to 3 per year)
SELECT e.EmployeeID, e.Y, 'Vacation', 'Annual', b.Len, CASE WHEN e.StartSeq > w.Lo THEN e.StartSeq ELSE w.Lo END, w.Hi, 5, b.K
FROM #EY e
CROSS APPLY (VALUES (1, e.P1, e.W1), (2, e.P2, e.W2), (3, e.P3, e.W3)) b(K, Len, W)
JOIN #Win w ON w.Y = e.Y AND w.W = b.W
WHERE b.K <= e.NOther AND b.Len IS NOT NULL;

INSERT INTO #Item (EmployeeID, Y, TypeName, Kind, Len, Lo, Hi, Prio, K)   -- sick episodes
SELECT e.EmployeeID, e.Y, 'Sick Leave', 'Sick',
       CASE WHEN h.u < 0.25 THEN 1 WHEN h.u < 0.50 THEN 2 WHEN h.u < 0.70 THEN 3 WHEN h.u < 0.85 THEN 4 ELSE 5 END,   -- 1-5 days: 25/25/20/15/15%
       e.StartSeq, e.EndSeq, 6, k.K
FROM #EY e JOIN (VALUES (1),(2),(3),(4),(5)) k(K) ON k.K <= e.NSick
CROSS APPLY (SELECT u = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', e.EmployeeID, '|', e.Y, '|s', k.K)), 1, 4) AS int) & 2147483647) / 2147483648.0) h;

-- order of placement inside each employee and year
UPDATE i SET Seq = n.rn
FROM #Item i JOIN (SELECT EmployeeID, Y, Prio, K, ROW_NUMBER() OVER (PARTITION BY EmployeeID, Y ORDER BY Prio, K) AS rn FROM #Item) n
     ON n.EmployeeID = i.EmployeeID AND n.Y = i.Y AND n.Prio = i.Prio AND n.K = i.K;

-- ================================================================ placement with retries (one item per employee and year at a time)
DECLARE @k int = 1, @maxk int = ISNULL((SELECT MAX(Seq) FROM #Item), 0), @t int;
WHILE @k <= @maxk
BEGIN
    SET @t = 1;
    WHILE @t <= 40
    BEGIN
        UPDATE i SET S = c.S
        FROM #Item i
        CROSS APPLY (SELECT S = i.Lo + CAST(FLOOR(((CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|place|', i.EmployeeID, '|', i.Y, '|', i.Prio, '|', i.K, '|', @t)), 1, 4) AS int) & 2147483647) / 2147483648.0)
                                                  * (i.Hi - i.Len + 1 - i.Lo + 1)) AS int)) c
        WHERE i.Seq = @k AND i.S IS NULL AND i.Hi - i.Lo + 1 >= i.Len
          AND NOT EXISTS (SELECT 1 FROM #Item o     -- no touching or overlapping with a leave already placed (one working day apart at least)
                          WHERE o.EmployeeID = i.EmployeeID AND o.Y = i.Y AND o.S IS NOT NULL
                            AND o.S - 1 <= c.S + i.Len - 1 AND o.S + o.Len - 1 + 1 >= c.S)
          AND NOT EXISTS (SELECT 1 FROM #Obs b
                          WHERE b.EmployeeID = i.EmployeeID AND b.S - 1 <= c.S + i.Len - 1 AND b.E + 1 >= c.S);
        SET @t += 1;
    END
    SET @k += 1;
END

-- ================================================================ leave rows
CREATE TABLE #L (EmployeeID int, Y int, TypeName varchar(30), Kind varchar(20), K int, S int, E int, StartDate date, EndDate date, HireDate date,
                 Lead int, Slow bit, Rej bit, Fast int, RequestDate date NULL, DecisionDate date NULL, Status varchar(10) NULL, ApproverID int NULL, Notes nvarchar(300) NULL);
INSERT INTO #L (EmployeeID, Y, TypeName, Kind, K, S, E, StartDate, EndDate, HireDate, Lead, Slow, Rej, Fast)
SELECT i.EmployeeID, i.Y, i.TypeName, i.Kind, i.K, i.S, i.S + i.Len - 1, a.D, b.D, x.HireDate,
       CASE i.Kind WHEN 'Sick' THEN 0 WHEN 'Bereavement' THEN 0 WHEN 'Parental' THEN 45 + CAST(FLOOR(h.lead * 106) AS int)
                   WHEN 'Unpaid' THEN 14 + CAST(FLOOR(h.lead * 47) AS int) ELSE 14 + CAST(FLOOR(h.lead * 137) AS int) END,
       CASE WHEN i.TypeName IN ('Vacation', 'Unpaid Leave', 'Parental Leave') AND h.slow < @pSlow THEN 1 ELSE 0 END,
       CASE WHEN i.TypeName IN ('Vacation', 'Unpaid Leave') AND h.rej < @pRejected THEN 1 ELSE 0 END,
       CAST(FLOOR(h.fast * 4) AS int)
FROM #Item i JOIN #WD a ON a.Seq = i.S JOIN #WD b ON b.Seq = i.S + i.Len - 1
JOIN #Emp x ON x.EmployeeID = i.EmployeeID
CROSS APPLY (SELECT
    lead = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|rq|', i.EmployeeID, '|', i.Y, '|', i.Prio, '|', i.K, '|lead')), 1, 4) AS int) & 2147483647) / 2147483648.0,
    slow = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|rq|', i.EmployeeID, '|', i.Y, '|', i.Prio, '|', i.K, '|slow')), 1, 4) AS int) & 2147483647) / 2147483648.0,
    rej  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|rq|', i.EmployeeID, '|', i.Y, '|', i.Prio, '|', i.K, '|rej')), 1, 4) AS int) & 2147483647) / 2147483648.0,
    fast = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|rq|', i.EmployeeID, '|', i.Y, '|', i.Prio, '|', i.K, '|fast')), 1, 4) AS int) & 2147483647) / 2147483648.0) h
WHERE i.S IS NOT NULL;

-- request date (not before the hire date, not after the start), decision date
UPDATE #L SET RequestDate = CASE WHEN DATEADD(DAY, -Lead, StartDate) < HireDate THEN HireDate ELSE DATEADD(DAY, -Lead, StartDate) END;
-- only the leaves requested in the period are written now (the approver needs the job history of the request date, which exists only up to the new end)
DELETE FROM #L WHERE RequestDate <= @Old OR RequestDate > @New;
UPDATE #L SET Slow = 0 WHERE Slow = 1 AND DATEDIFF(DAY, RequestDate, StartDate) < 21;     -- too late for a long decision
UPDATE #L SET DecisionDate = CASE WHEN Slow = 1 THEN DATEADD(DAY, -14, StartDate)
                                  WHEN DATEADD(DAY, Fast, RequestDate) > StartDate THEN StartDate ELSE DATEADD(DAY, Fast, RequestDate) END;
UPDATE #L SET Status = CASE WHEN Rej = 1 THEN 'Rejected' ELSE 'Approved' END;

-- approver: the manager on the request date (job history); the CEO's leave goes to the CHRO
UPDATE l SET ApproverID = ISNULL(j.ManagerEmployeeID, @Chro)
FROM #L l JOIN dbo.EmployeeJobHistory j ON j.EmployeeID = l.EmployeeID AND j.EffectiveDate <= l.RequestDate AND (j.EndDate IS NULL OR j.EndDate > l.RequestDate);

UPDATE #L SET Notes = CASE
    WHEN Status = 'Rejected' THEN N'Request declined because of team coverage in that period'
    WHEN Kind = 'Summer'     THEN N'Summer vacation'
    WHEN Kind = 'Annual'     THEN N'Annual vacation'
    WHEN Kind = 'Sick'       THEN N'Short absence reported to the manager'
    WHEN Kind = 'Parental'   THEN N'Parental leave'
    WHEN Kind = 'Unpaid'     THEN N'Unpaid leave'
    WHEN Kind = 'Bereavement' THEN N'Bereavement leave' END;

IF EXISTS (SELECT 1 FROM #L WHERE Status IS NULL OR ApproverID IS NULL OR RequestDate IS NULL OR DecisionDate IS NULL OR RequestDate > StartDate OR DecisionDate < RequestDate)
    THROW 50030, 'Some new leaves have no status, approver or valid dates.', 1;

-- add the leaves whose request date falls in the period (a leave that is already stored is not added again)
INSERT INTO dbo.EmployeeLeaves (EmployeeID, LeaveTypeID, StartDate, EndDate, Status, ApprovedByEmployeeID, Notes)
SELECT l.EmployeeID, t.LeaveTypeID, l.StartDate, l.EndDate, l.Status, l.ApproverID, l.Notes
FROM #L l JOIN dbo.LeaveTypes t ON t.LeaveTypeName = CASE l.TypeName WHEN 'Vacation' THEN N'Vacation' WHEN 'Sick Leave' THEN N'Sick Leave'
                                                         WHEN 'Parental Leave' THEN N'Parental Leave' WHEN 'Unpaid Leave' THEN N'Unpaid Leave' ELSE N'Bereavement' END
WHERE l.RequestDate > @Old AND l.RequestDate <= @New
  AND NOT EXISTS (SELECT 1 FROM dbo.EmployeeLeaves x WHERE x.EmployeeID = l.EmployeeID AND x.StartDate = l.StartDate)
ORDER BY l.RequestDate, l.EmployeeID;

INSERT INTO dbo.LeaveRequestInfo (LeaveID, RequestDate, DecisionDate, FinalStatus, ApprovedByEmployeeID, IsNew)
SELECT x.LeaveID, l.RequestDate, l.DecisionDate, l.Status, l.ApproverID, 1
FROM #L l JOIN dbo.EmployeeLeaves x ON x.EmployeeID = l.EmployeeID AND x.StartDate = l.StartDate AND x.EndDate = l.EndDate
WHERE NOT EXISTS (SELECT 1 FROM dbo.LeaveRequestInfo i WHERE i.LeaveID = x.LeaveID)
  AND l.RequestDate > @Old AND l.RequestDate <= @New;

-- the Pending requests of the first load: when they are decided, how, and by whom (their rows stay as they are)
INSERT INTO dbo.LeaveRequestInfo (LeaveID, RequestDate, DecisionDate, FinalStatus, ApprovedByEmployeeID, IsNew)
SELECT l.LeaveID, '2026-11-16',
       CASE WHEN DATEADD(DAY, -14, l.StartDate) > '2026-11-17' THEN DATEADD(DAY, -14, l.StartDate) ELSE CAST('2026-11-17' AS date) END,
       CASE WHEN (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|pending|', l.LeaveID)), 1, 4) AS int) & 2147483647) / 2147483648.0 < @pRejected THEN 'Rejected' ELSE 'Approved' END,
       ISNULL(j.ManagerEmployeeID, @Chro), 0
FROM dbo.EmployeeLeaves l
JOIN dbo.EmployeeJobHistory j ON j.EmployeeID = l.EmployeeID AND j.EffectiveDate <= '2026-11-16' AND (j.EndDate IS NULL OR j.EndDate > '2026-11-16')
WHERE l.Status = 'Pending' AND NOT EXISTS (SELECT 1 FROM dbo.LeaveRequestInfo i WHERE i.LeaveID = l.LeaveID);

-- no overlapping leave for one employee
IF EXISTS (SELECT 1 FROM dbo.EmployeeLeaves a JOIN dbo.EmployeeLeaves b ON b.EmployeeID = a.EmployeeID AND b.LeaveID > a.LeaveID
           AND a.StartDate <= b.EndDate AND b.StartDate <= a.EndDate)
    THROW 50031, 'Two leaves of one employee overlap.', 1;

SELECT YEAR(l.StartDate) AS StartYear, t.LeaveTypeName AS Type, COUNT(*) AS NewLeaves,
       SUM(CASE WHEN l.Status = 'Rejected' THEN 1 ELSE 0 END) AS Rejected, SUM(CASE WHEN i.DecisionDate > i.RequestDate AND DATEDIFF(DAY, i.RequestDate, i.DecisionDate) > 3 THEN 1 ELSE 0 END) AS DecidedLate
FROM dbo.EmployeeLeaves l JOIN dbo.LeaveTypes t ON t.LeaveTypeID = l.LeaveTypeID
JOIN dbo.LeaveRequestInfo i ON i.LeaveID = l.LeaveID AND i.IsNew = 1
JOIN #Run r ON i.RequestDate > r.OldDate AND i.RequestDate <= r.NewDate
GROUP BY YEAR(l.StartDate), t.LeaveTypeName ORDER BY 1, 2;

DROP TABLE #WD, #Yr, #Win, #Obs, #Emp, #EY, #Item, #L;
