-- 06_reviews.sql: annual performance reviews held in the period (#Run.OldDate, #Run.NewDate] (step 6 of sql/extend_data.sql)
-- Same rules as 10_generate_reviews.sql, one review per employee and calendar year Y (period 1 Jan - 31 Dec), held on a working day
-- between 20 January and 15 March of year Y + 1:
--   * eligible: has a manager (not the CEO) and was hired on or before 1 July of Y; about 4% of the eligible reviews are left out;
--   * reviewer: the manager on 31 December of Y (from EmployeeJobHistory);
--   * rating: 3.45 + a personal baseline (the same hash as in script 10, sd 0.40) + a yearly variation (sd 0.40), rounded to 1 decimal,
--     clipped to 1.0-5.0, so the levels are about 4% / 46% / 46% / 4% (the "year before a promotion" bump of script 10 is not used,
--     the promotion is not known yet when the review is written);
--   * comment: a short template sentence for the performance level.
-- A review is added when its date falls in the period, so the result does not depend on how often the update runs; a review that already
-- exists for that employee and year is left alone. Runs inside the transaction opened by 02_log_run.sql. Only inserts.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Seed      varchar(20) = 'DemoHR-2026';   -- the seed of script 10, so a person keeps the same baseline
DECLARE @pOmit     float       = 0.04;
DECLARE @BaseMean  float       = 3.45;
DECLARE @BaseSd    float       = 0.40;
DECLARE @YearSd    float       = 0.40;

CREATE TABLE #Tpl (PerformanceLevel varchar(30), Idx int, Txt nvarchar(500), PRIMARY KEY (PerformanceLevel, Idx));
INSERT INTO #Tpl VALUES
('Needs Improvement',1,N'Performance was below expectations this year; a structured improvement plan with clear targets and regular check-ins is recommended.'),
('Needs Improvement',2,N'Key objectives were not consistently met; additional coaching and a focused development plan will support progress next year.'),
('Needs Improvement',3,N'Results fell short of the agreed goals; priorities and expectations will be reset with monthly follow-up.'),
('Needs Improvement',4,N'Several deliverables were delayed or incomplete; support and training will be arranged to help close the gaps.'),
('Meets Expectations',1,N'Met the main objectives for the year and delivered reliable, steady work.'),
('Meets Expectations',2,N'Performance was consistent with expectations; there is room to take on more responsibility and broaden skills.'),
('Meets Expectations',3,N'Delivered the agreed results and worked well with colleagues; continued focus on development is encouraged.'),
('Meets Expectations',4,N'Solid contribution this year, meeting goals on time and keeping quality at the expected level.'),
('Exceeds Expectations',1,N'Exceeded the agreed goals and delivered high-quality work, often ahead of schedule.'),
('Exceeds Expectations',2,N'Strong results this year; showed initiative and supported the team beyond the usual scope of the role.'),
('Exceeds Expectations',3,N'Consistently delivered above expectations and contributed ideas that improved the way the team works.'),
('Exceeds Expectations',4,N'Very good performance; a dependable contributor who raised the standard for those around them.'),
('Outstanding',1,N'Outstanding year with exceptional results and a clear positive impact on the whole team.'),
('Outstanding',2,N'Delivered far above expectations and acted as a role model for quality, ownership and collaboration.'),
('Outstanding',3,N'Exceptional performance across all objectives; ready for broader responsibility.'),
('Outstanding',4,N'Top results this year and a major contribution to the success of the department.');

-- working days 20 Jan - 15 Mar of each year Y + 1 whose reviews can fall in the period
CREATE TABLE #WD (Y int, Seq int, D date, Cnt int, PRIMARY KEY (Y, Seq));
;WITH y AS (
    SELECT YEAR(OldDate) - 1 AS Y FROM #Run
    UNION ALL SELECT Y + 1 FROM y WHERE Y < (SELECT YEAR(NewDate) FROM #Run) - 1
), d AS (
    SELECT y.Y, DATEFROMPARTS(y.Y + 1, 1, 20) AS D FROM y
    UNION ALL
    SELECT Y, DATEADD(DAY, 1, D) FROM d WHERE D < DATEFROMPARTS(Y + 1, 3, 15)
), w AS (
    SELECT Y, D FROM d
    WHERE DATEDIFF(DAY, '19000101', D) % 7 < 5
      AND NOT EXISTS (SELECT 1 FROM dbo.PublicHolidays h WHERE h.HolidayDate = d.D)
)
INSERT INTO #WD (Y, Seq, D, Cnt)
SELECT Y, ROW_NUMBER() OVER (PARTITION BY Y ORDER BY D), D, COUNT(*) OVER (PARTITION BY Y) FROM w
OPTION (MAXRECURSION 0);

CREATE TABLE #Rv (EmployeeID int, Y int, ReviewerID int, ReviewDate date, Draw float, HCmt int,
                  Rating decimal(2,1) NULL, Lvl varchar(30) NULL, PRIMARY KEY (EmployeeID, Y));

;WITH cand AS (
    SELECT e.EmployeeID, y.Y
    FROM dbo.Employees e
    CROSS JOIN (SELECT DISTINCT Y FROM #WD) y
    WHERE e.HireDate <= DATEFROMPARTS(y.Y, 7, 1)
), hh AS (
    SELECT c.EmployeeID, c.Y, h.HOmit, h.HDate, h.HU1, h.HU2, h.HCmt, h.HB1, h.HB2
    FROM cand c
    CROSS APPLY (SELECT HOmit = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', c.EmployeeID, '|', c.Y, '|omit')), 1, 4) AS int) & 2147483647,
                        HDate = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', c.EmployeeID, '|', c.Y, '|date')), 1, 4) AS int) & 2147483647,
                        HU1   = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', c.EmployeeID, '|', c.Y, '|u1')), 1, 4) AS int) & 2147483647,
                        HU2   = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', c.EmployeeID, '|', c.Y, '|u2')), 1, 4) AS int) & 2147483647,
                        HCmt  = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', c.EmployeeID, '|', c.Y, '|cmt')), 1, 4) AS int) & 2147483647,
                        HB1   = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', c.EmployeeID, '|b1')), 1, 4) AS int) & 2147483647,
                        HB2   = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', c.EmployeeID, '|b2')), 1, 4) AS int) & 2147483647) h
    WHERE h.HOmit / 2147483648.0 >= @pOmit
      AND NOT EXISTS (SELECT 1 FROM dbo.PerformanceReviews r WHERE r.EmployeeID = c.EmployeeID AND r.ReviewPeriodEnd = DATEFROMPARTS(c.Y, 12, 31))
)
INSERT INTO #Rv (EmployeeID, Y, ReviewerID, ReviewDate, Draw, HCmt)
SELECT hh.EmployeeID, hh.Y, j.ManagerEmployeeID, w.D,
       @BaseSd * SQRT(-2.0 * LOG((hh.HB1 + 1.0) / 2147483649.0)) * COS(2 * PI() * (hh.HB2 / 2147483648.0))
     + @YearSd * SQRT(-2.0 * LOG((hh.HU1 + 1.0) / 2147483649.0)) * COS(2 * PI() * (hh.HU2 / 2147483648.0)),
       hh.HCmt
FROM hh
JOIN dbo.EmployeeJobHistory j ON j.EmployeeID = hh.EmployeeID AND j.EffectiveDate <= DATEFROMPARTS(hh.Y, 12, 31)
                              AND (j.EndDate IS NULL OR j.EndDate > DATEFROMPARTS(hh.Y, 12, 31))      -- manager on 31 December
JOIN #WD w ON w.Y = hh.Y AND w.Seq = 1 + CAST(FLOOR(hh.HDate / 2147483648.0 * w.Cnt) AS int)
WHERE w.D > (SELECT OldDate FROM #Run) AND w.D <= (SELECT NewDate FROM #Run) AND j.ManagerEmployeeID IS NOT NULL;

UPDATE #Rv SET Rating = CAST(CASE WHEN ROUND(@BaseMean + Draw, 1) < 1.0 THEN 1.0 WHEN ROUND(@BaseMean + Draw, 1) > 5.0 THEN 5.0
                                  ELSE ROUND(@BaseMean + Draw, 1) END AS decimal(2,1));
UPDATE #Rv SET Lvl = CASE WHEN Rating < 2.5 THEN 'Needs Improvement' WHEN Rating < 3.5 THEN 'Meets Expectations'
                          WHEN Rating < 4.5 THEN 'Exceeds Expectations' ELSE 'Outstanding' END;

INSERT INTO dbo.PerformanceReviews (EmployeeID, ReviewerEmployeeID, ReviewDate, ReviewPeriodStart, ReviewPeriodEnd, OverallRating, PerformanceLevel, Comments)
SELECT r.EmployeeID, r.ReviewerID, r.ReviewDate, DATEFROMPARTS(r.Y, 1, 1), DATEFROMPARTS(r.Y, 12, 31), r.Rating, r.Lvl, t.Txt
FROM #Rv r JOIN #Tpl t ON t.PerformanceLevel = r.Lvl AND t.Idx = 1 + (r.HCmt % 4)
ORDER BY r.Y, r.EmployeeID;

SELECT Y AS ReviewYear, COUNT(*) AS NewReviews, MIN(ReviewDate) AS FirstDate, MAX(ReviewDate) AS LastDate,
       CAST(AVG(CAST(Rating AS float)) AS decimal(3,2)) AS AvgRating
FROM #Rv GROUP BY Y ORDER BY Y;

DROP TABLE #Tpl, #WD, #Rv;
