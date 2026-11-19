-- 11_generate_leave.sql: leave records 2024-01-01 .. 2027-03-31 (past, current and booked leave).
-- Deterministic: every random value is a hash of (seed, employee / item, label).
-- Working days = Monday-Friday that are not in dbo.PublicHolidays. Start and end dates are always working days;
-- a leave of N working days covers N working days (weekends and holidays inside it are not counted).
--
--   Vacation       22-28 working days a year in 2-4 blocks: one summer block of 10-15 days between 1 June and 15 August,
--                  the other blocks in Jan-May, 16 Aug-Oct and Nov-Dec. Partial years (hired during the year) are scaled.
--                  2027 (Jan-Mar only): one block of 5-10 days for 70% of employees.
--                  Past (start <= reference date): 97% Approved / 3% Rejected. Booked (start after it): 80% Approved / 20% Pending.
--   Sick Leave     0-5 episodes a year of 1-5 working days (about 7 a year), Approved, never after the reference date.
--   Parental Leave about 4% of employees, one block of 30-120 working days, any gender.
--   Unpaid Leave   about 2% of employees, 5-20 working days.      Bereavement  about 3% of employees, 1-3 working days.
--   Approver       the employee's manager on the start date (job history); the CEO's leave is approved by the CHRO;
--                  Pending leaves have no approver.
--   Placement      long and rare leave first (parental, unpaid, bereavement), then vacation blocks, then sick episodes;
--                  an item that cannot be placed without touching another leave of the same employee is dropped.
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -f 65001 -i sql/11_generate_leave.sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Seed     varchar(20) = 'DemoHR-2026';
DECLARE @RefDate  date        = '2026-11-16';   -- reference date ("today"); the only place it is written
DECLARE @WinStart date        = '2024-01-01';
DECLARE @WinEnd   date        = '2027-03-31';
DECLARE @pParental float = 0.04, @pUnpaid float = 0.02, @pBereave float = 0.03;
DECLARE @pRejected float = 0.03, @pPending float = 0.20, @p2027 float = 0.70;

BEGIN TRANSACTION;

-- ================================================================ working-day calendar
CREATE TABLE #WD (Seq int PRIMARY KEY, D date NOT NULL UNIQUE, Y int NOT NULL);
;WITH d AS (SELECT @WinStart AS D UNION ALL SELECT DATEADD(DAY, 1, D) FROM d WHERE D < @WinEnd)
INSERT INTO #WD (Seq, D, Y)
SELECT ROW_NUMBER() OVER (ORDER BY D), D, YEAR(D) FROM d
WHERE DATEDIFF(DAY, '19000101', D) % 7 < 5                          -- 1900-01-01 was a Monday
  AND NOT EXISTS (SELECT 1 FROM dbo.PublicHolidays h WHERE h.HolidayDate = d.D)
OPTION (MAXRECURSION 0);

DECLARE @N      int = (SELECT MAX(Seq) FROM #WD);
DECLARE @SeqRef int = (SELECT MAX(Seq) FROM #WD WHERE D <= @RefDate);
DECLARE @Chro   int = (SELECT e.EmployeeID FROM dbo.Employees e JOIN dbo.Positions p ON p.PositionID = e.PositionID WHERE p.PositionTitle = N'Chief Human Resources Officer');

-- years and the windows inside each year (as working-day sequence numbers)
CREATE TABLE #Yr  (Y int PRIMARY KEY, FirstSeq int, LastSeq int);
INSERT INTO #Yr SELECT Y, MIN(Seq), MAX(Seq) FROM #WD GROUP BY Y;
CREATE TABLE #Win (Y int, W char(1), Lo int, Hi int, PRIMARY KEY (Y, W));      -- A Jan-May, S 1 Jun-15 Aug, B 16 Aug-Oct, C Nov-Dec
INSERT INTO #Win
SELECT y.Y, w.W,
       (SELECT MIN(Seq) FROM #WD WHERE D >= DATEFROMPARTS(y.Y, w.M1, w.D1)),
       (SELECT MAX(Seq) FROM #WD WHERE D <= DATEFROMPARTS(y.Y, w.M2, w.D2))
FROM #Yr y CROSS JOIN (VALUES ('A',1,1,5,31),('S',6,1,8,15),('B',8,16,10,31),('C',11,1,12,31)) w(W, M1, D1, M2, D2);
-- 2027 only runs to the end of March: window A is Jan-Mar
UPDATE #Win SET Hi = @N WHERE Y = 2027 AND W = 'A';
DELETE FROM #Win WHERE Y = 2027 AND W <> 'A';

-- ================================================================ employees and the rare leave types
CREATE TABLE #Emp (EmployeeID int PRIMARY KEY, HireDate date, HireSeq int,
                   Rpar float, Rparl float, Runp float, Runpl float, Rber float, Rberl float, Parental bit, Unpaid bit, Bereave bit);
INSERT INTO #Emp (EmployeeID, HireDate, HireSeq, Rpar, Rparl, Runp, Runpl, Rber, Rberl, Parental, Unpaid, Bereave)
SELECT e.EmployeeID, e.HireDate, ISNULL((SELECT MIN(Seq) FROM #WD WHERE D >= e.HireDate), @N + 1),
       (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', e.EmployeeID, '|par')),  1, 4) AS int) & 2147483647) / 2147483648.0,
       (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', e.EmployeeID, '|parl')), 1, 4) AS int) & 2147483647) / 2147483648.0,
       (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', e.EmployeeID, '|unp')),  1, 4) AS int) & 2147483647) / 2147483648.0,
       (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', e.EmployeeID, '|unpl')), 1, 4) AS int) & 2147483647) / 2147483648.0,
       (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', e.EmployeeID, '|ber')),  1, 4) AS int) & 2147483647) / 2147483648.0,
       (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', e.EmployeeID, '|berl')), 1, 4) AS int) & 2147483647) / 2147483648.0,
       0, 0, 0
FROM dbo.Employees e;

DECLARE @Total int = (SELECT COUNT(*) FROM #Emp);
-- exactly 4% / 2% / 3% of employees (those with the lowest hash among people with at least a year of service)
UPDATE x SET Parental = 1 FROM #Emp x JOIN (SELECT EmployeeID, ROW_NUMBER() OVER (ORDER BY Rpar) AS rk FROM #Emp WHERE HireDate < DATEADD(MONTH, -12, @RefDate)) q ON q.EmployeeID = x.EmployeeID WHERE q.rk <= ROUND(@pParental * @Total, 0);
UPDATE x SET Unpaid   = 1 FROM #Emp x JOIN (SELECT EmployeeID, ROW_NUMBER() OVER (ORDER BY Runp) AS rk FROM #Emp WHERE HireDate < DATEADD(MONTH, -12, @RefDate)) q ON q.EmployeeID = x.EmployeeID WHERE q.rk <= ROUND(@pUnpaid * @Total, 0);
UPDATE x SET Bereave  = 1 FROM #Emp x JOIN (SELECT EmployeeID, ROW_NUMBER() OVER (ORDER BY Rber) AS rk FROM #Emp WHERE HireDate < DATEADD(MONTH, -12, @RefDate)) q ON q.EmployeeID = x.EmployeeID WHERE q.rk <= ROUND(@pBereave * @Total, 0);

-- ================================================================ employee-year plans (2024-2026): vacation blocks and sick episodes
CREATE TABLE #EY (EmployeeID int, Y int, StartSeq int, EndSeq int, YLen int, Frac float, SickEnd int,
                  rvt float, rvn float, rvs float, rp1 float, rp2 float, rwa float, rwb float, rwc float, rse float, rse2 float,
                  rs1 float, rs2 float, rs3 float, rs4 float, rs5 float,
                  T int NULL, N0 int NULL, HasSum bit NULL, S int NULL, NOther int NULL, R int NULL, P1 int NULL, P2 int NULL, P3 int NULL,
                  W1 char(1) NULL, W2 char(1) NULL, W3 char(1) NULL, NSick int NULL,
                  PRIMARY KEY (EmployeeID, Y));
INSERT INTO #EY (EmployeeID, Y, StartSeq, EndSeq, YLen, Frac, SickEnd, rvt, rvn, rvs, rp1, rp2, rwa, rwb, rwc, rse, rse2, rs1, rs2, rs3, rs4, rs5)
SELECT x.EmployeeID, y.Y, s.StartSeq, y.LastSeq, y.LastSeq - y.FirstSeq + 1,
       (y.LastSeq - s.StartSeq + 1.0) / (y.LastSeq - y.FirstSeq + 1),
       CASE WHEN y.LastSeq < @SeqRef THEN y.LastSeq ELSE @SeqRef END,
       r.vt, r.vn, r.vs, r.p1, r.p2, r.wa, r.wb, r.wc, r.se, r.se2, r.s1, r.s2, r.s3, r.s4, r.s5
FROM #Emp x
JOIN #Yr y ON y.Y BETWEEN 2024 AND 2026
CROSS APPLY (SELECT StartSeq = CASE WHEN x.HireSeq > y.FirstSeq THEN x.HireSeq ELSE y.FirstSeq END) s
CROSS APPLY (SELECT
    vt  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|vt')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    vn  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|vn')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    vs  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|vs')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    p1  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|p1')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    p2  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|p2')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    wa  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|wa')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    wb  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|wb')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    wc  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|wc')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    se  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|se')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    se2 = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|se2')), 1, 4) AS int) & 2147483647) / 2147483648.0,
    s1  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|s1')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    s2  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|s2')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    s3  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|s3')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    s4  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|s4')),  1, 4) AS int) & 2147483647) / 2147483648.0,
    s5  = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|', y.Y, '|s5')),  1, 4) AS int) & 2147483647) / 2147483648.0) r
WHERE s.StartSeq <= y.LastSeq;

-- vacation total (22-28, scaled for part-years), number of blocks, summer block
UPDATE #EY SET T  = CASE WHEN Frac >= 0.999 THEN 22 + CAST(FLOOR(rvt * 7) AS int) ELSE CAST(ROUND((22 + FLOOR(rvt * 7)) * Frac, 0) AS int) END,
               N0 = 2 + CAST(FLOOR(rvn * 3) AS int);
UPDATE e SET HasSum = CASE WHEN e.T >= 14 AND e.StartSeq <= w.Lo THEN 1 ELSE 0 END
FROM #EY e JOIN #Win w ON w.Y = e.Y AND w.W = 'S';
UPDATE #EY SET S = CASE WHEN HasSum = 1 THEN CASE WHEN 10 + CAST(FLOOR(rvs * 6) AS int) > T - 4 THEN T - 4 ELSE 10 + CAST(FLOOR(rvs * 6) AS int) END END;
UPDATE #EY SET HasSum = 0, S = NULL WHERE HasSum = 1 AND S < 5;
UPDATE #EY SET R = T - ISNULL(S, 0);
UPDATE #EY SET NOther = CASE WHEN R < 2 THEN 0
                             ELSE (SELECT MIN(v) FROM (VALUES (CASE WHEN HasSum = 1 THEN N0 - 1 ELSE N0 END), (3), (R / 2)) t(v)) END;
-- split R into NOther parts of at least 2 days
UPDATE #EY SET P1 = CASE NOther WHEN 1 THEN R WHEN 2 THEN 2 + CAST(FLOOR(rp1 * (R - 4 + 1)) AS int) WHEN 3 THEN 2 + CAST(FLOOR(rp1 * (R - 6 + 1)) AS int) END WHERE NOther >= 1;
UPDATE #EY SET P2 = CASE NOther WHEN 2 THEN R - P1 WHEN 3 THEN 2 + CAST(FLOOR(rp2 * ((R - P1) - 4 + 1)) AS int) END WHERE NOther >= 2;
UPDATE #EY SET P3 = R - P1 - P2 WHERE NOther = 3;
-- which windows the other blocks use (random order of A, B, C)
UPDATE #EY SET W1 = CASE WHEN (CASE WHEN rwb < rwa THEN 1 ELSE 0 END + CASE WHEN rwc < rwa THEN 1 ELSE 0 END) = 0 THEN 'A'
                         WHEN (CASE WHEN rwa <= rwb THEN 1 ELSE 0 END + CASE WHEN rwc < rwb THEN 1 ELSE 0 END) = 0 THEN 'B' ELSE 'C' END,
               W3 = CASE WHEN (CASE WHEN rwb < rwa THEN 1 ELSE 0 END + CASE WHEN rwc < rwa THEN 1 ELSE 0 END) = 2 THEN 'A'
                         WHEN (CASE WHEN rwa <= rwb THEN 1 ELSE 0 END + CASE WHEN rwc < rwb THEN 1 ELSE 0 END) = 2 THEN 'B' ELSE 'C' END;
UPDATE #EY SET W2 = CASE WHEN 'A' NOT IN (W1, W3) THEN 'A' WHEN 'B' NOT IN (W1, W3) THEN 'B' ELSE 'C' END;
-- sick episodes: 0-5 a year, evenly spread over the employee-years (by hash rank, so the average does not depend on luck),
-- scaled by the share of the year that is employed and already past
;WITH q AS (SELECT EmployeeID, Y, FLOOR(6.0 * (ROW_NUMBER() OVER (ORDER BY rse, EmployeeID, Y) - 1) / COUNT(*) OVER ()) AS E0 FROM #EY)
UPDATE e SET NSick = CASE WHEN e.SickEnd < e.StartSeq THEN 0
                          WHEN FLOOR(q.E0 * ((e.SickEnd - e.StartSeq + 1.0) / e.YLen) + e.rse2) > 5 THEN 5
                          ELSE CAST(FLOOR(q.E0 * ((e.SickEnd - e.StartSeq + 1.0) / e.YLen) + e.rse2) AS int) END
FROM #EY e JOIN q ON q.EmployeeID = e.EmployeeID AND q.Y = e.Y;

-- ================================================================ items to place
CREATE TABLE #Item (ItemID int IDENTITY(1,1) PRIMARY KEY, EmployeeID int, Y int NULL, TypeName varchar(30), Kind varchar(20), Len int, Lo int, Hi int,
                    Prio int, K int, Seq int NULL, S int NULL);

INSERT INTO #Item (EmployeeID, Y, TypeName, Kind, Len, Lo, Hi, Prio, K)   -- parental, unpaid, bereavement
SELECT EmployeeID, NULL, 'Parental Leave', 'Parental', 30 + CAST(FLOOR(Rparl * 91) AS int), HireSeq, @N, 1, 1 FROM #Emp WHERE Parental = 1
UNION ALL
SELECT EmployeeID, NULL, 'Unpaid Leave', 'Unpaid', 5 + CAST(FLOOR(Runpl * 16) AS int), HireSeq, @N, 2, 1 FROM #Emp WHERE Unpaid = 1
UNION ALL
SELECT EmployeeID, NULL, 'Bereavement', 'Bereavement', 1 + CAST(FLOOR(Rberl * 3) AS int), HireSeq, @SeqRef, 3, 1 FROM #Emp WHERE Bereave = 1;

INSERT INTO #Item (EmployeeID, Y, TypeName, Kind, Len, Lo, Hi, Prio, K)   -- summer block
SELECT e.EmployeeID, e.Y, 'Vacation', 'Summer', e.S, CASE WHEN e.StartSeq > w.Lo THEN e.StartSeq ELSE w.Lo END, w.Hi, 4, 0
FROM #EY e JOIN #Win w ON w.Y = e.Y AND w.W = 'S' WHERE e.HasSum = 1 ORDER BY e.EmployeeID, e.Y;

INSERT INTO #Item (EmployeeID, Y, TypeName, Kind, Len, Lo, Hi, Prio, K)   -- the other vacation blocks (1 to 3 per year)
SELECT e.EmployeeID, e.Y, 'Vacation', 'Annual', b.Len, CASE WHEN e.StartSeq > w.Lo THEN e.StartSeq ELSE w.Lo END, w.Hi, 5, b.K
FROM #EY e
CROSS APPLY (VALUES (1, e.P1, e.W1), (2, e.P2, e.W2), (3, e.P3, e.W3)) b(K, Len, W)
JOIN #Win w ON w.Y = e.Y AND w.W = b.W
WHERE b.K <= e.NOther AND b.Len IS NOT NULL ORDER BY e.EmployeeID, e.Y, b.K;

INSERT INTO #Item (EmployeeID, Y, TypeName, Kind, Len, Lo, Hi, Prio, K)   -- 2027 (January-March): one block for 70% of employees
SELECT x.EmployeeID, 2027, 'Vacation', 'Winter', 5 + CAST(FLOOR(r.l * 6) AS int), CASE WHEN x.HireSeq > w.Lo THEN x.HireSeq ELSE w.Lo END, w.Hi, 5, 1
FROM #Emp x JOIN #Win w ON w.Y = 2027 AND w.W = 'A'
CROSS APPLY (SELECT p = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|27p')), 1, 4) AS int) & 2147483647) / 2147483648.0,
                    l = (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|', x.EmployeeID, '|27l')), 1, 4) AS int) & 2147483647) / 2147483648.0) r
WHERE r.p < @p2027 ORDER BY x.EmployeeID;

INSERT INTO #Item (EmployeeID, Y, TypeName, Kind, Len, Lo, Hi, Prio, K)   -- sick episodes
SELECT z.EmployeeID, z.Y, 'Sick Leave', 'Sick',
       CASE WHEN (z.rk - 0.5) / z.cnt < 0.25 THEN 1 WHEN (z.rk - 0.5) / z.cnt < 0.50 THEN 2 WHEN (z.rk - 0.5) / z.cnt < 0.70 THEN 3
            WHEN (z.rk - 0.5) / z.cnt < 0.85 THEN 4 ELSE 5 END,       -- 1-5 days, evenly spread by hash rank: 25/25/20/15/15%, mean 2.8
       z.StartSeq, z.SickEnd, 6, z.K
FROM (SELECT e.EmployeeID, e.Y, e.StartSeq, e.SickEnd, k.K,
             ROW_NUMBER() OVER (ORDER BY CASE k.K WHEN 1 THEN e.rs1 WHEN 2 THEN e.rs2 WHEN 3 THEN e.rs3 WHEN 4 THEN e.rs4 ELSE e.rs5 END, e.EmployeeID, e.Y, k.K) AS rk,
             COUNT(*) OVER () AS cnt
      FROM #EY e JOIN (VALUES (1),(2),(3),(4),(5)) k(K) ON k.K <= e.NSick) z
ORDER BY z.EmployeeID, z.Y, z.K;

-- order of placement inside each employee
UPDATE i SET Seq = n.rn
FROM #Item i JOIN (SELECT ItemID, ROW_NUMBER() OVER (PARTITION BY EmployeeID ORDER BY Prio, ISNULL(Y, 0), K, ItemID) AS rn FROM #Item) n ON n.ItemID = i.ItemID;

-- ================================================================ placement with retries (one item per employee at a time)
DECLARE @k int = 1, @maxk int = (SELECT MAX(Seq) FROM #Item), @t int;
WHILE @k <= @maxk
BEGIN
    SET @t = 1;
    WHILE @t <= 40
    BEGIN
        UPDATE i SET S = c.S
        FROM #Item i
        CROSS APPLY (SELECT S = i.Lo + CAST(FLOOR(((CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|place|', i.ItemID, '|', @t)), 1, 4) AS int) & 2147483647) / 2147483648.0)
                                                  * (i.Hi - i.Len + 1 - i.Lo + 1)) AS int)) c
        WHERE i.Seq = @k AND i.S IS NULL AND i.Hi - i.Lo + 1 >= i.Len
          AND NOT EXISTS (SELECT 1 FROM #Item o     -- no touching or overlapping with a leave already placed (one working day apart at least)
                          WHERE o.EmployeeID = i.EmployeeID AND o.S IS NOT NULL
                            AND o.S - 1 <= c.S + i.Len - 1 AND o.S + o.Len - 1 + 1 >= c.S);
        SET @t += 1;
    END
    SET @k += 1;
END

-- ================================================================ leave rows: dates, status, approver, notes
CREATE TABLE #L (EmployeeID int, TypeName varchar(30), Kind varchar(20), S int, E int, StartDate date, EndDate date,
                 Status varchar(10) NULL, ApproverID int NULL, Notes nvarchar(300) NULL, PRIMARY KEY (EmployeeID, S));
INSERT INTO #L (EmployeeID, TypeName, Kind, S, E, StartDate, EndDate)
SELECT i.EmployeeID, i.TypeName, i.Kind, i.S, i.S + i.Len - 1, a.D, b.D
FROM #Item i JOIN #WD a ON a.Seq = i.S JOIN #WD b ON b.Seq = i.S + i.Len - 1
WHERE i.S IS NOT NULL;

-- status: vacation and unpaid are 97% Approved / 3% Rejected when past (start on or before the reference date)
-- and 80% Approved / 20% Pending when booked; parental is Approved when past, 80/20 when booked; sick and bereavement Approved.
;WITH x AS (
    SELECT l.EmployeeID, l.S, l.TypeName, CASE WHEN l.StartDate <= @RefDate THEN 0 ELSE 1 END AS Future,
           ROW_NUMBER() OVER (PARTITION BY l.TypeName, CASE WHEN l.StartDate <= @RefDate THEN 0 ELSE 1 END
                              ORDER BY HASHBYTES('SHA2_256', CONCAT(@Seed, '|lv|st|', l.EmployeeID, '|', l.S))) AS rk,
           COUNT(*) OVER (PARTITION BY l.TypeName, CASE WHEN l.StartDate <= @RefDate THEN 0 ELSE 1 END) AS cnt
    FROM #L l)
UPDATE l SET Status =
    CASE WHEN x.Future = 0 THEN CASE WHEN l.TypeName IN ('Vacation', 'Unpaid Leave') AND x.rk <= ROUND(@pRejected * x.cnt, 0) THEN 'Rejected' ELSE 'Approved' END
         ELSE CASE WHEN l.TypeName IN ('Vacation', 'Unpaid Leave', 'Parental Leave') AND x.rk <= ROUND(@pPending * x.cnt, 0) THEN 'Pending' ELSE 'Approved' END END
FROM #L l JOIN x ON x.EmployeeID = l.EmployeeID AND x.S = l.S;

-- approver: the manager on the start date from job history; the CEO's leave goes to the CHRO; Pending has none
UPDATE l SET ApproverID = CASE WHEN l.Status = 'Pending' THEN NULL ELSE ISNULL(j.ManagerEmployeeID, @Chro) END
FROM #L l JOIN dbo.EmployeeJobHistory j ON j.EmployeeID = l.EmployeeID AND j.EffectiveDate <= l.StartDate AND (j.EndDate IS NULL OR j.EndDate > l.StartDate);

-- notes: short and generic, no health details
UPDATE #L SET Notes = CASE
    WHEN Status = 'Rejected' THEN N'Request declined because of team coverage in that period'
    WHEN Status = 'Pending'  THEN N'Waiting for manager approval'
    WHEN Kind = 'Summer'     THEN N'Summer vacation'
    WHEN Kind = 'Annual'     THEN N'Annual vacation'
    WHEN Kind = 'Winter'     THEN N'Winter vacation'
    WHEN Kind = 'Sick'       THEN N'Short absence reported to the manager'
    WHEN Kind = 'Parental'   THEN N'Parental leave'
    WHEN Kind = 'Unpaid'     THEN N'Unpaid leave'
    WHEN Kind = 'Bereavement' THEN N'Bereavement leave' END;

IF EXISTS (SELECT 1 FROM #L WHERE Status IS NULL OR (Status <> 'Pending' AND ApproverID IS NULL)) THROW 50020, 'Some leaves have no status or approver.', 1;

-- ================================================================ write to EmployeeLeaves (clears only this table)
DELETE FROM dbo.EmployeeLeaves;
DECLARE @seedLv int = CASE WHEN EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.EmployeeLeaves') AND last_value IS NULL) THEN 1 ELSE 0 END;
DBCC CHECKIDENT ('dbo.EmployeeLeaves', RESEED, @seedLv) WITH NO_INFOMSGS;

INSERT INTO dbo.EmployeeLeaves (EmployeeID, LeaveTypeID, StartDate, EndDate, Status, ApprovedByEmployeeID, Notes)
SELECT l.EmployeeID, t.LeaveTypeID, l.StartDate, l.EndDate, l.Status, l.ApproverID, l.Notes
FROM #L l JOIN dbo.LeaveTypes t ON t.LeaveTypeName = CASE l.TypeName WHEN 'Vacation' THEN N'Vacation' WHEN 'Sick Leave' THEN N'Sick Leave'
                                                         WHEN 'Parental Leave' THEN N'Parental Leave' WHEN 'Unpaid Leave' THEN N'Unpaid Leave' ELSE N'Bereavement' END
ORDER BY l.EmployeeID, l.StartDate;

COMMIT TRANSACTION;

-- ================================================================ checks
-- working days of every stored leave, through the calendar (a start or end that is not a working day finds no row)
SELECT l.LeaveID, l.EmployeeID, t.LeaveTypeName AS TypeName, l.StartDate, l.EndDate, l.Status, l.ApprovedByEmployeeID, l.Notes,
       sd.Seq AS S, ed.Seq AS E, ed.Seq - sd.Seq + 1 AS Days
INTO #V
FROM dbo.EmployeeLeaves l JOIN dbo.LeaveTypes t ON t.LeaveTypeID = l.LeaveTypeID
LEFT JOIN #WD sd ON sd.D = l.StartDate LEFT JOIN #WD ed ON ed.D = l.EndDate;

PRINT '--- 1. Window and dates (violations, expect 0)';
SELECT COUNT(*) AS Leaves, MIN(StartDate) AS FirstStart, MAX(EndDate) AS LastEnd,
       SUM(CASE WHEN StartDate < '2024-01-01' OR EndDate > '2027-03-31' THEN 1 ELSE 0 END) AS OutsideWindow,
       SUM(CASE WHEN S IS NULL OR E IS NULL THEN 1 ELSE 0 END) AS StartOrEndNotWorkingDay,
       SUM(CASE WHEN EndDate < StartDate THEN 1 ELSE 0 END) AS EndBeforeStart,
       (SELECT COUNT(*) FROM #V v JOIN dbo.Employees e ON e.EmployeeID = v.EmployeeID WHERE v.StartDate < e.HireDate) AS StartsBeforeHire,
       (SELECT COUNT(*) FROM #V a JOIN #V b ON b.EmployeeID = a.EmployeeID AND b.LeaveID > a.LeaveID AND a.StartDate <= b.EndDate AND b.StartDate <= a.EndDate) AS OverlappingLeaves
FROM #V;

PRINT '--- 2a. Vacation 2024-2026, employees employed the whole year and without parental leave: days a year, blocks, summer block';
;WITH fy AS (
    SELECT e.EmployeeID, y.Y FROM dbo.Employees e CROSS JOIN (VALUES (2024),(2025),(2026)) y(Y)
    WHERE e.HireDate < DATEFROMPARTS(y.Y, 1, 1)
      AND NOT EXISTS (SELECT 1 FROM #V p WHERE p.EmployeeID = e.EmployeeID AND p.TypeName = N'Parental Leave')),
vy AS (
    SELECT fy.EmployeeID, fy.Y, ISNULL(SUM(v.Days), 0) AS Days, COUNT(v.LeaveID) AS Blocks,
           SUM(CASE WHEN v.StartDate >= DATEFROMPARTS(fy.Y, 6, 1) AND v.EndDate <= DATEFROMPARTS(fy.Y, 8, 15) THEN 1 ELSE 0 END) AS SummerBlocks,
           SUM(CASE WHEN v.StartDate >= DATEFROMPARTS(fy.Y, 6, 1) AND v.EndDate <= DATEFROMPARTS(fy.Y, 8, 15) AND v.Days BETWEEN 10 AND 15 THEN 1 ELSE 0 END) AS SummerOk
    FROM fy LEFT JOIN #V v ON v.EmployeeID = fy.EmployeeID AND v.TypeName = N'Vacation' AND YEAR(v.StartDate) = fy.Y
    GROUP BY fy.EmployeeID, fy.Y)
SELECT Y AS [Year], COUNT(*) AS EmployeeYears, MIN(Days) AS MinDays, CAST(AVG(1.0 * Days) AS decimal(4,1)) AS AvgDays, MAX(Days) AS MaxDays,
       SUM(CASE WHEN Days NOT BETWEEN 22 AND 28 THEN 1 ELSE 0 END) AS Not22to28,
       MIN(Blocks) AS MinBlocks, MAX(Blocks) AS MaxBlocks, SUM(CASE WHEN Blocks NOT BETWEEN 2 AND 4 THEN 1 ELSE 0 END) AS Not2to4Blocks,
       SUM(CASE WHEN SummerBlocks <> 1 OR SummerOk <> 1 THEN 1 ELSE 0 END) AS SummerBlockProblems
FROM vy GROUP BY Y ORDER BY Y;

PRINT '--- 2b. Vacation status: past (start on or before the reference date) vs booked (start after it)';
SELECT CASE WHEN StartDate <= @RefDate THEN 'Past/current' ELSE 'Booked' END AS Period, COUNT(*) AS Blocks,
       SUM(CASE WHEN Status = 'Approved' THEN 1 ELSE 0 END) AS Approved, SUM(CASE WHEN Status = 'Rejected' THEN 1 ELSE 0 END) AS Rejected, SUM(CASE WHEN Status = 'Pending' THEN 1 ELSE 0 END) AS Pending,
       CAST(100.0 * SUM(CASE WHEN Status = 'Approved' THEN 1 ELSE 0 END) / COUNT(*) AS decimal(4,1)) AS PctApproved,
       CAST(100.0 * SUM(CASE WHEN Status = 'Rejected' THEN 1 ELSE 0 END) / COUNT(*) AS decimal(4,1)) AS PctRejected,
       CAST(100.0 * SUM(CASE WHEN Status = 'Pending' THEN 1 ELSE 0 END) / COUNT(*) AS decimal(4,1)) AS PctPending
FROM #V WHERE TypeName = N'Vacation' GROUP BY CASE WHEN StartDate <= @RefDate THEN 'Past/current' ELSE 'Booked' END;

PRINT '--- 3a. Sick Leave: episodes a year (0-5), days per episode (1-5), average days a year, status, never after the reference date';
;WITH fy AS (
    SELECT e.EmployeeID, y.Y FROM dbo.Employees e CROSS JOIN (VALUES (2024),(2025)) y(Y) WHERE e.HireDate < DATEFROMPARTS(y.Y, 1, 1)),
sy AS (
    SELECT fy.EmployeeID, fy.Y, COUNT(v.LeaveID) AS Episodes, ISNULL(SUM(v.Days), 0) AS Days
    FROM fy LEFT JOIN #V v ON v.EmployeeID = fy.EmployeeID AND v.TypeName = N'Sick Leave' AND YEAR(v.StartDate) = fy.Y GROUP BY fy.EmployeeID, fy.Y)
SELECT COUNT(*) AS EmployeeYears_2024_2025, MIN(Episodes) AS MinEpisodes, MAX(Episodes) AS MaxEpisodes, CAST(AVG(1.0 * Episodes) AS decimal(3,1)) AS AvgEpisodes,
       CAST(AVG(1.0 * Days) AS decimal(4,1)) AS AvgSickDaysPerYear,
       (SELECT MIN(Days) FROM #V WHERE TypeName = N'Sick Leave') AS MinDaysPerEpisode, (SELECT MAX(Days) FROM #V WHERE TypeName = N'Sick Leave') AS MaxDaysPerEpisode,
       (SELECT COUNT(*) FROM #V WHERE TypeName = N'Sick Leave' AND Status <> 'Approved') AS SickNotApproved,
       (SELECT COUNT(*) FROM #V WHERE TypeName = N'Sick Leave' AND EndDate > @RefDate) AS SickAfterReferenceDate
FROM sy;

PRINT '--- 3b. Parental, Unpaid and Bereavement: share of employees, length in working days, gender (parental)';
SELECT TypeName, COUNT(DISTINCT EmployeeID) AS Employees, CAST(100.0 * COUNT(DISTINCT EmployeeID) / (SELECT COUNT(*) FROM dbo.Employees) AS decimal(4,1)) AS PctOfEmployees,
       COUNT(*) AS Leaves, MIN(Days) AS MinDays, MAX(Days) AS MaxDays,
       SUM(CASE WHEN TypeName = N'Bereavement' AND EndDate > @RefDate THEN 1 ELSE 0 END) AS BereavementAfterReferenceDate
FROM #V WHERE TypeName IN (N'Parental Leave', N'Unpaid Leave', N'Bereavement') GROUP BY TypeName ORDER BY TypeName;
SELECT e.Gender, COUNT(*) AS ParentalLeaves, MIN(v.Days) AS MinDays, MAX(v.Days) AS MaxDays
FROM #V v JOIN dbo.Employees e ON e.EmployeeID = v.EmployeeID WHERE v.TypeName = N'Parental Leave' GROUP BY e.Gender;

PRINT '--- 4. Approvals (violations, expect 0)';
SELECT (SELECT COUNT(*) FROM #V WHERE Status = 'Pending' AND ApprovedByEmployeeID IS NOT NULL) AS PendingWithApprover,
       (SELECT COUNT(*) FROM #V WHERE Status IN ('Approved', 'Rejected') AND ApprovedByEmployeeID IS NULL) AS ApprovedOrRejectedWithoutApprover,
       (SELECT COUNT(*) FROM #V v
        WHERE v.ApprovedByEmployeeID IS NOT NULL AND v.ApprovedByEmployeeID <> ISNULL(
              (SELECT j.ManagerEmployeeID FROM dbo.EmployeeJobHistory j WHERE j.EmployeeID = v.EmployeeID AND j.EffectiveDate <= v.StartDate AND (j.EndDate IS NULL OR j.EndDate > v.StartDate)), @Chro)) AS ApproverNotManagerOnStartDate,
       (SELECT COUNT(*) FROM #V v JOIN dbo.Employees e ON e.EmployeeID = v.EmployeeID WHERE e.ManagerEmployeeID IS NULL AND v.ApprovedByEmployeeID IS NOT NULL AND v.ApprovedByEmployeeID <> @Chro) AS CeoLeaveNotApprovedByChro,
       (SELECT COUNT(*) FROM #V v JOIN dbo.Employees a ON a.EmployeeID = v.ApprovedByEmployeeID WHERE a.HireDate > v.StartDate) AS ApproverNotEmployedOnStartDate,
       (SELECT COUNT(*) FROM #V WHERE ApprovedByEmployeeID = EmployeeID) AS SelfApproved,
       (SELECT COUNT(*) FROM #V v JOIN dbo.Employees e ON e.EmployeeID = v.EmployeeID WHERE e.ManagerEmployeeID IS NULL) AS CeoLeaves;

PRINT '--- 5. Absent on the reference date: employees on approved leave';
SELECT e.EmployeeNumber, e.FirstName + N' ' + e.LastName AS Employee, u.UnitName AS Department, v.TypeName AS LeaveType, v.StartDate, v.EndDate, v.Days
FROM #V v JOIN dbo.Employees e ON e.EmployeeID = v.EmployeeID JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = e.OrganizationUnitID
WHERE v.Status = 'Approved' AND v.StartDate <= @RefDate AND v.EndDate >= @RefDate ORDER BY v.TypeName, e.EmployeeNumber;
SELECT COUNT(DISTINCT EmployeeID) AS EmployeesOnApprovedLeaveOnReferenceDate FROM #V WHERE Status = 'Approved' AND StartDate <= @RefDate AND EndDate >= @RefDate;

PRINT '--- 6a. Working days by leave type';
SELECT TypeName, COUNT(*) AS Leaves, SUM(Days) AS WorkingDays_AllStatuses,
       SUM(CASE WHEN Status = 'Approved' THEN Days ELSE 0 END) AS WorkingDays_Approved,
       SUM(CASE WHEN Status = 'Rejected' THEN Days ELSE 0 END) AS WorkingDays_Rejected,
       SUM(CASE WHEN Status = 'Pending'  THEN Days ELSE 0 END) AS WorkingDays_Pending
FROM #V GROUP BY TypeName ORDER BY SUM(Days) DESC;
PRINT '--- 6b. Average vacation days per employee per year (employees employed the whole year; all statuses / approved only)';
SELECT y.Y AS [Year], COUNT(*) AS Employees,
       CAST(AVG(1.0 * ISNULL(a.AllDays, 0)) AS decimal(4,1)) AS AvgVacationDays_All,
       CAST(AVG(1.0 * ISNULL(a.ApprDays, 0)) AS decimal(4,1)) AS AvgVacationDays_Approved
FROM (VALUES (2024),(2025),(2026)) y(Y)
JOIN dbo.Employees e ON e.HireDate < DATEFROMPARTS(y.Y, 1, 1)
OUTER APPLY (SELECT SUM(v.Days) AS AllDays, SUM(CASE WHEN v.Status = 'Approved' THEN v.Days ELSE 0 END) AS ApprDays
             FROM #V v WHERE v.EmployeeID = e.EmployeeID AND v.TypeName = N'Vacation' AND YEAR(v.StartDate) = y.Y) a
GROUP BY y.Y ORDER BY y.Y;

PRINT '--- 7. Notes: distinct texts and health-detail words (hits, expect 0)';
SELECT Notes, COUNT(*) AS Leaves FROM #V GROUP BY Notes ORDER BY COUNT(*) DESC;
SELECT SUM(CASE WHEN Notes LIKE '%diagnos%' OR Notes LIKE '%flu%' OR Notes LIKE '%cold%' OR Notes LIKE '%covid%' OR Notes LIKE '%surgery%' OR Notes LIKE '%hospital%'
                  OR Notes LIKE '%doctor%' OR Notes LIKE '%medical%' OR Notes LIKE '%illness%' OR Notes LIKE '%injur%' OR Notes LIKE '%therapy%' OR Notes LIKE '%cancer%'
                  OR Notes LIKE '%depress%' OR Notes LIKE '%pregnan%' OR Notes LIKE '%fever%' OR Notes LIKE '%migraine%' OR Notes LIKE '%back pain%' THEN 1 ELSE 0 END) AS HealthWordHits,
       MAX(LEN(Notes)) AS MaxNoteLength
FROM #V;

DROP TABLE #V, #L, #Item, #EY, #Emp, #Win, #Yr, #WD;
GO
