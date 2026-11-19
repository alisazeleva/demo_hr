-- 10_generate_reviews.sql: annual performance reviews.
-- Deterministic: every random value is a hash of (seed, employee ID, year, label).
--
--   * One review per employee per calendar year (period 1 Jan - 31 Dec), 2012 up to the last year whose review
--     is already held on the reference date (2025 for 2026-11-16). No reviews for the current year.
--   * Review date: a working day (no weekend, no Finnish public holiday) from 20 January to 15 March of the next year.
--   * Eligible: hired on or before 1 July of the review year, and not the CEO (no manager = no reviewer).
--     About 4% of eligible reviews are left out.
--   * Reviewer: the employee's manager on 31 December of the review year, taken from EmployeeJobHistory.
--   * Rating = personal baseline + yearly variation + 0.3 in the year before a promotion, rounded to 1 decimal,
--     clipped to 1.0-5.0. Baseline ~ N(3.45, 0.40), yearly ~ N(0, 0.40): total sd ~0.57, so the level shares are
--     about 4% / 46% / 46% / 4% (3.45 because ratings are rounded half-up before the 3.5 / 2.5 / 4.5 thresholds).
--   * Comments: short templated sentences per performance level, nothing personal.
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -f 65001 -i sql/10_generate_reviews.sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @Seed      varchar(20) = 'DemoHR-2026';
DECLARE @RefDate   date        = '2026-11-16';   -- reference date ("today"); the only place it is written
DECLARE @FirstYear int         = 2012;
DECLARE @LastYear  int         = YEAR(@RefDate) - 1;   -- latest review year already held (reviews are in Jan-Mar of the next year)
DECLARE @pOmit     float       = 0.04;           -- share of eligible reviews left out
DECLARE @BaseMean  float       = 3.45;
DECLARE @BaseSd    float       = 0.40;
DECLARE @YearSd    float       = 0.40;
DECLARE @PromoBump float       = 0.30;

BEGIN TRANSACTION;

-- ================================================================ comment templates (script-local)
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

-- ================================================================ working days 20 Jan - 15 Mar of each following year
CREATE TABLE #WD (Y int, Seq int, D date, Cnt int, PRIMARY KEY (Y, Seq));
;WITH y AS (SELECT @FirstYear AS Y UNION ALL SELECT Y + 1 FROM y WHERE Y < @LastYear),
d AS (
    SELECT y.Y, DATEFROMPARTS(y.Y + 1, 1, 20) AS D FROM y
    UNION ALL
    SELECT Y, DATEADD(DAY, 1, D) FROM d WHERE D < DATEFROMPARTS(Y + 1, 3, 15)
), w AS (
    SELECT Y, D FROM d
    WHERE DATEDIFF(DAY, '19000101', D) % 7 < 5                      -- 1900-01-01 was a Monday
      AND NOT EXISTS (SELECT 1 FROM dbo.PublicHolidays h WHERE h.HolidayDate = d.D)
      AND D <= @RefDate
)
INSERT INTO #WD (Y, Seq, D, Cnt)
SELECT Y, ROW_NUMBER() OVER (PARTITION BY Y ORDER BY D), D, COUNT(*) OVER (PARTITION BY Y) FROM w
OPTION (MAXRECURSION 0);

-- ================================================================ personal baseline per employee (normal draw)
CREATE TABLE #B (EmployeeID int PRIMARY KEY, Zb float);
INSERT INTO #B
SELECT e.EmployeeID, z.Z
FROM dbo.Employees e
CROSS APPLY (SELECT H1 = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', e.EmployeeID, '|b1')), 1, 4) AS int) & 2147483647,
                    H2 = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', e.EmployeeID, '|b2')), 1, 4) AS int) & 2147483647) h
CROSS APPLY (SELECT Z = SQRT(-2.0 * LOG((h.H1 + 1.0) / 2147483649.0)) * COS(2 * PI() * (h.H2 / 2147483648.0))) z;

-- ================================================================ reviews
CREATE TABLE #Rv (EmployeeID int, Y int, ReviewerID int, ReviewDate date, Draw float, Bump float, HCmt int,
                  Rating decimal(2,1) NULL, Lvl varchar(30) NULL, Cmt nvarchar(500) NULL, PRIMARY KEY (EmployeeID, Y));
DECLARE @Eligible int;

;WITH yrs AS (SELECT @FirstYear AS Y UNION ALL SELECT Y + 1 FROM yrs WHERE Y < @LastYear),
cand AS (   -- eligible: not the CEO (has a manager), hired by 1 July of the year
    SELECT e.EmployeeID, y.Y
    FROM dbo.Employees e CROSS JOIN yrs y
    WHERE e.ManagerEmployeeID IS NOT NULL AND e.HireDate <= DATEFROMPARTS(y.Y, 7, 1)
), hh AS (
    SELECT c.EmployeeID, c.Y, h.HDate, h.HU1, h.HU2, h.HCmt,
           ROW_NUMBER() OVER (ORDER BY h.HOmit, c.EmployeeID, c.Y) AS Rk, COUNT(*) OVER () AS Tot
    FROM cand c
    CROSS APPLY (SELECT HOmit = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', c.EmployeeID, '|', c.Y, '|omit')), 1, 4) AS int) & 2147483647,
                        HDate = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', c.EmployeeID, '|', c.Y, '|date')), 1, 4) AS int) & 2147483647,
                        HU1   = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', c.EmployeeID, '|', c.Y, '|u1')), 1, 4) AS int) & 2147483647,
                        HU2   = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', c.EmployeeID, '|', c.Y, '|u2')), 1, 4) AS int) & 2147483647,
                        HCmt  = CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|rev|', c.EmployeeID, '|', c.Y, '|cmt')), 1, 4) AS int) & 2147483647) h
)
INSERT INTO #Rv (EmployeeID, Y, ReviewerID, ReviewDate, Draw, Bump, HCmt)
SELECT hh.EmployeeID, hh.Y, j.ManagerEmployeeID, w.D,
       @BaseSd * b.Zb + @YearSd * SQRT(-2.0 * LOG((hh.HU1 + 1.0) / 2147483649.0)) * COS(2 * PI() * (hh.HU2 / 2147483648.0)),
       CASE WHEN EXISTS (SELECT 1 FROM dbo.EmployeeJobHistory p
                         WHERE p.EmployeeID = hh.EmployeeID AND p.ChangeType IN ('Promotion', 'Promotion + Department Transfer')
                           AND YEAR(p.EffectiveDate) = hh.Y + 1) THEN @PromoBump ELSE 0 END,
       hh.HCmt
FROM hh
JOIN #B b ON b.EmployeeID = hh.EmployeeID
JOIN dbo.EmployeeJobHistory j ON j.EmployeeID = hh.EmployeeID AND j.EffectiveDate <= DATEFROMPARTS(hh.Y, 12, 31)
                              AND (j.EndDate IS NULL OR j.EndDate > DATEFROMPARTS(hh.Y, 12, 31))      -- manager on 31 December
JOIN #WD w ON w.Y = hh.Y AND w.Seq = 1 + CAST(FLOOR(hh.HDate / 2147483648.0 * w.Cnt) AS int)
WHERE hh.Rk > ROUND(@pOmit * hh.Tot, 0);        -- exactly 4% of the eligible reviews (the ones with the lowest hash) are left out

SET @Eligible = (SELECT COUNT(*) FROM dbo.Employees e JOIN (SELECT TOP (@LastYear - @FirstYear + 1) @FirstYear - 1 + ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS Y FROM sys.all_objects) y
                 ON e.ManagerEmployeeID IS NOT NULL AND e.HireDate <= DATEFROMPARTS(y.Y, 7, 1));

-- Standardise the random part (baseline + yearly variation) over all reviews to mean 0 and sd sqrt(BaseSd^2 + YearSd^2),
-- so the rating mix does not depend on sampling luck; then add the centre and the pre-promotion bump.
;WITH s AS (SELECT AVG(Draw) AS M, STDEV(Draw) AS Sd FROM #Rv)
UPDATE r SET Draw = (r.Draw - s.M) / s.Sd * SQRT(@BaseSd * @BaseSd + @YearSd * @YearSd) FROM #Rv r CROSS JOIN s;

UPDATE #Rv SET Rating = CAST(CASE WHEN ROUND(@BaseMean + Draw + Bump, 1) < 1.0 THEN 1.0 WHEN ROUND(@BaseMean + Draw + Bump, 1) > 5.0 THEN 5.0
                                  ELSE ROUND(@BaseMean + Draw + Bump, 1) END AS decimal(2,1));
UPDATE #Rv SET Lvl = CASE WHEN Rating < 2.5 THEN 'Needs Improvement' WHEN Rating < 3.5 THEN 'Meets Expectations'
                          WHEN Rating < 4.5 THEN 'Exceeds Expectations' ELSE 'Outstanding' END;
UPDATE r SET Cmt = t.Txt FROM #Rv r JOIN #Tpl t ON t.PerformanceLevel = r.Lvl AND t.Idx = 1 + (r.HCmt % 4);

-- ================================================================ write to PerformanceReviews (clears only this table)
DELETE FROM dbo.PerformanceReviews;
DECLARE @seedPr int = CASE WHEN EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.PerformanceReviews') AND last_value IS NULL) THEN 1 ELSE 0 END;
DBCC CHECKIDENT ('dbo.PerformanceReviews', RESEED, @seedPr) WITH NO_INFOMSGS;

INSERT INTO dbo.PerformanceReviews (EmployeeID, ReviewerEmployeeID, ReviewDate, ReviewPeriodStart, ReviewPeriodEnd, OverallRating, PerformanceLevel, Comments)
SELECT EmployeeID, ReviewerID, ReviewDate, DATEFROMPARTS(Y, 1, 1), DATEFROMPARTS(Y, 12, 31), Rating, Lvl, Cmt
FROM #Rv ORDER BY Y, EmployeeID;
IF EXISTS (SELECT 1 FROM #Rv WHERE Rating IS NULL OR Cmt IS NULL) THROW 50011, 'Some reviews are incomplete.', 1;

COMMIT TRANSACTION;

-- ================================================================ checks
PRINT '--- 1. Annual structure: reviews per year (period 1 Jan - 31 Dec, review date 20 Jan - 15 Mar next year, working day)';
SELECT YEAR(ReviewPeriodEnd) AS ReviewYear, COUNT(*) AS Reviews, MIN(ReviewDate) AS FirstReviewDate, MAX(ReviewDate) AS LastReviewDate
FROM dbo.PerformanceReviews GROUP BY YEAR(ReviewPeriodEnd) ORDER BY 1;

;WITH pr AS (
    SELECT p.*, CASE WHEN EXISTS (SELECT 1 FROM dbo.PublicHolidays h WHERE h.HolidayDate = p.ReviewDate) THEN 1 ELSE 0 END AS IsHoliday
    FROM dbo.PerformanceReviews p)
SELECT COUNT(*) AS Reviews, MAX(YEAR(ReviewPeriodEnd)) AS LatestReviewYear,
       SUM(CASE WHEN YEAR(ReviewPeriodEnd) >= YEAR(@RefDate) THEN 1 ELSE 0 END) AS ReviewsForCurrentYear,
       SUM(CASE WHEN ReviewPeriodStart <> DATEFROMPARTS(YEAR(ReviewPeriodEnd), 1, 1) OR ReviewPeriodEnd <> DATEFROMPARTS(YEAR(ReviewPeriodEnd), 12, 31) THEN 1 ELSE 0 END) AS PeriodNotCalendarYear,
       SUM(CASE WHEN ReviewDate < DATEFROMPARTS(YEAR(ReviewPeriodEnd) + 1, 1, 20) OR ReviewDate > DATEFROMPARTS(YEAR(ReviewPeriodEnd) + 1, 3, 15) THEN 1 ELSE 0 END) AS DateOutsideWindow,
       SUM(CASE WHEN DATEDIFF(DAY, '19000101', ReviewDate) % 7 >= 5 OR IsHoliday = 1 THEN 1 ELSE 0 END) AS DateNotWorkingDay,
       SUM(CASE WHEN ReviewDate > @RefDate THEN 1 ELSE 0 END) AS DateAfterReferenceDate
FROM pr;

PRINT '--- 2. Eligibility: hired by 1 July of the review year; about 4% of eligible reviews left out';
SELECT (SELECT COUNT(*) FROM dbo.PerformanceReviews r JOIN dbo.Employees e ON e.EmployeeID = r.EmployeeID WHERE e.HireDate > DATEFROMPARTS(YEAR(r.ReviewPeriodEnd), 7, 1)) AS ReviewsForNotYetEligible,
       (SELECT COUNT(*) FROM dbo.PerformanceReviews r JOIN dbo.Employees e ON e.EmployeeID = r.EmployeeID WHERE r.ReviewDate <= e.HireDate) AS ReviewsBeforeHire,
       @Eligible AS EligibleReviews, COUNT(*) AS ReviewsWritten, @Eligible - COUNT(*) AS LeftOut,
       CAST(100.0 * (@Eligible - COUNT(*)) / @Eligible AS decimal(4,1)) AS PctLeftOut
FROM dbo.PerformanceReviews;

PRINT '--- 2b. Employees with no review in the last 12 months (review dates after 12 months before the reference date)';
;WITH recent AS (
    SELECT e.EmployeeID, e.HireDate, e.ManagerEmployeeID,
           (SELECT COUNT(*) FROM dbo.PerformanceReviews r WHERE r.EmployeeID = e.EmployeeID AND r.ReviewDate > DATEADD(MONTH, -12, @RefDate) AND r.ReviewDate <= @RefDate) AS N
    FROM dbo.Employees e)
SELECT COUNT(*) AS Employees,
       SUM(CASE WHEN N > 0 THEN 1 ELSE 0 END) AS WithRecentReview,
       SUM(CASE WHEN N = 0 THEN 1 ELSE 0 END) AS NoRecentReview,
       SUM(CASE WHEN N = 0 AND ManagerEmployeeID IS NULL THEN 1 ELSE 0 END) AS ofWhichCEO,
       SUM(CASE WHEN N = 0 AND ManagerEmployeeID IS NOT NULL AND HireDate > DATEFROMPARTS(YEAR(@RefDate) - 1, 7, 1) THEN 1 ELSE 0 END) AS ofWhichHiredAfter1July,
       SUM(CASE WHEN N = 0 AND ManagerEmployeeID IS NOT NULL AND HireDate <= DATEFROMPARTS(YEAR(@RefDate) - 1, 7, 1) THEN 1 ELSE 0 END) AS ofWhichLeftOut
FROM recent;

PRINT '--- 3. Reviewer = the employee''s manager on 31 December of the period, from job history (rows that differ, expect 0)';
SELECT (SELECT COUNT(*) FROM dbo.PerformanceReviews r
        WHERE NOT EXISTS (SELECT 1 FROM dbo.EmployeeJobHistory j WHERE j.EmployeeID = r.EmployeeID AND j.ManagerEmployeeID = r.ReviewerEmployeeID
                          AND j.EffectiveDate <= r.ReviewPeriodEnd AND (j.EndDate IS NULL OR j.EndDate > r.ReviewPeriodEnd))) AS ReviewerNotManagerOn31Dec,
       (SELECT COUNT(*) FROM dbo.PerformanceReviews r JOIN dbo.Employees m ON m.EmployeeID = r.ReviewerEmployeeID WHERE m.HireDate > r.ReviewDate) AS ReviewerHiredAfterReviewDate,
       (SELECT COUNT(*) FROM dbo.PerformanceReviews WHERE EmployeeID = ReviewerEmployeeID) AS SelfReviews,
       (SELECT COUNT(*) FROM dbo.PerformanceReviews r JOIN dbo.Employees e ON e.EmployeeID = r.EmployeeID WHERE e.ManagerEmployeeID IS NULL) AS CEOReviews,
       (SELECT COUNT(DISTINCT ReviewerEmployeeID) FROM dbo.PerformanceReviews) AS DistinctReviewers;

PRINT '--- 4. Ratings: range, one decimal, level matches rating, level shares (targets about 4 / 46 / 46 / 4 %)';
SELECT MIN(OverallRating) AS MinRating, MAX(OverallRating) AS MaxRating, CAST(AVG(OverallRating) AS decimal(4,2)) AS AvgRating,
       SUM(CASE WHEN OverallRating < 1.0 OR OverallRating > 5.0 THEN 1 ELSE 0 END) AS OutOfRange,
       SUM(CASE WHEN CAST(OverallRating * 10 AS decimal(5,1)) % 1 <> 0 THEN 1 ELSE 0 END) AS MoreThanOneDecimal,
       SUM(CASE WHEN PerformanceLevel <> CASE WHEN OverallRating < 2.5 THEN 'Needs Improvement' WHEN OverallRating < 3.5 THEN 'Meets Expectations'
                                              WHEN OverallRating < 4.5 THEN 'Exceeds Expectations' ELSE 'Outstanding' END THEN 1 ELSE 0 END) AS LevelMismatch
FROM dbo.PerformanceReviews;
SELECT PerformanceLevel, COUNT(*) AS Reviews, CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS decimal(4,1)) AS Pct,
       MIN(OverallRating) AS MinRating, MAX(OverallRating) AS MaxRating
FROM dbo.PerformanceReviews GROUP BY PerformanceLevel
ORDER BY CASE PerformanceLevel WHEN 'Needs Improvement' THEN 1 WHEN 'Meets Expectations' THEN 2 WHEN 'Exceeds Expectations' THEN 3 ELSE 4 END;

PRINT '--- 5a. Promotion effect: rating in the year before a promotion vs the same employees'' other years (expect about +0.3)';
;WITH r AS (
    SELECT pr.EmployeeID, pr.OverallRating,
           CASE WHEN EXISTS (SELECT 1 FROM dbo.EmployeeJobHistory p WHERE p.EmployeeID = pr.EmployeeID AND p.ChangeType IN ('Promotion', 'Promotion + Department Transfer')
                             AND YEAR(p.EffectiveDate) = YEAR(pr.ReviewPeriodEnd) + 1) THEN 1 ELSE 0 END AS BeforePromo
    FROM dbo.PerformanceReviews pr),
per AS (
    SELECT EmployeeID, AVG(CASE WHEN BeforePromo = 1 THEN OverallRating END) AS PromoYr, AVG(CASE WHEN BeforePromo = 0 THEN OverallRating END) AS Other
    FROM r GROUP BY EmployeeID HAVING SUM(BeforePromo) > 0 AND SUM(1 - BeforePromo) > 0)
SELECT (SELECT COUNT(*) FROM r WHERE BeforePromo = 1) AS ReviewsYearBeforePromotion,
       (SELECT CAST(AVG(OverallRating) AS decimal(4,2)) FROM r WHERE BeforePromo = 1) AS AvgYearBefore,
       (SELECT CAST(AVG(OverallRating) AS decimal(4,2)) FROM r WHERE BeforePromo = 0) AS AvgOtherYears,
       COUNT(*) AS EmployeesWithBoth, CAST(AVG(PromoYr - Other) AS decimal(4,2)) AS PairedDifference
FROM per;

PRINT '--- 5b. Average rating by department and level (department and level on 31 December of the review year)';
SELECT u.UnitName AS Department, p.JobLevel AS Level, COUNT(*) AS Reviews, CAST(AVG(r.OverallRating) AS decimal(4,2)) AS AvgRating
FROM dbo.PerformanceReviews r
JOIN dbo.EmployeeJobHistory j ON j.EmployeeID = r.EmployeeID AND j.EffectiveDate <= r.ReviewPeriodEnd AND (j.EndDate IS NULL OR j.EndDate > r.ReviewPeriodEnd)
JOIN dbo.Positions p ON p.PositionID = j.PositionID
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = j.OrganizationUnitID
GROUP BY u.OrganizationUnitID, u.UnitName, p.JobLevelRank, p.JobLevel ORDER BY u.OrganizationUnitID, p.JobLevelRank;

PRINT '--- 5c. Average rating by department, by level and by gender';
SELECT u.UnitName AS Department, COUNT(*) AS Reviews, CAST(AVG(r.OverallRating) AS decimal(4,2)) AS AvgRating
FROM dbo.PerformanceReviews r
JOIN dbo.EmployeeJobHistory j ON j.EmployeeID = r.EmployeeID AND j.EffectiveDate <= r.ReviewPeriodEnd AND (j.EndDate IS NULL OR j.EndDate > r.ReviewPeriodEnd)
JOIN dbo.OrganizationUnits u ON u.OrganizationUnitID = j.OrganizationUnitID
GROUP BY u.OrganizationUnitID, u.UnitName ORDER BY u.OrganizationUnitID;
SELECT p.JobLevel AS Level, COUNT(*) AS Reviews, CAST(AVG(r.OverallRating) AS decimal(4,2)) AS AvgRating
FROM dbo.PerformanceReviews r
JOIN dbo.EmployeeJobHistory j ON j.EmployeeID = r.EmployeeID AND j.EffectiveDate <= r.ReviewPeriodEnd AND (j.EndDate IS NULL OR j.EndDate > r.ReviewPeriodEnd)
JOIN dbo.Positions p ON p.PositionID = j.PositionID
GROUP BY p.JobLevelRank, p.JobLevel ORDER BY p.JobLevelRank;
SELECT e.Gender, COUNT(*) AS Reviews, COUNT(DISTINCT e.EmployeeID) AS Employees, CAST(AVG(r.OverallRating) AS decimal(4,2)) AS AvgRating,
       CAST(100.0 * SUM(CASE WHEN r.PerformanceLevel IN ('Exceeds Expectations', 'Outstanding') THEN 1 ELSE 0 END) / COUNT(*) AS decimal(4,1)) AS PctExceedsOrOutstanding
FROM dbo.PerformanceReviews r JOIN dbo.Employees e ON e.EmployeeID = r.EmployeeID GROUP BY e.Gender;

PRINT '--- 6. Comments: templates per level, length, no personal or health words (hits, expect 0), one sample per level';
SELECT COUNT(DISTINCT Comments) AS DistinctComments, MAX(LEN(Comments)) AS MaxLength,
       SUM(CASE WHEN Comments IS NULL THEN 1 ELSE 0 END) AS NullComments,
       SUM(CASE WHEN Comments LIKE '%sick%' OR Comments LIKE '%illness%' OR Comments LIKE '%health%' OR Comments LIKE '%medical%'
                  OR Comments LIKE '%pregnan%' OR Comments LIKE '%maternity%' OR Comments LIKE '%parental%' OR Comments LIKE '%family%' OR Comments LIKE '%divorce%'
                  OR Comments LIKE '% age %' OR Comments LIKE '%gender%' OR Comments LIKE '%nationalit%' OR Comments LIKE '% he %' OR Comments LIKE '% she %'
                  OR Comments LIKE '% his %' OR Comments LIKE '% her %' OR Comments LIKE '% him %' OR Comments LIKE '% ill %' THEN 1 ELSE 0 END) AS PersonalOrHealthWordHits
FROM dbo.PerformanceReviews;
SELECT PerformanceLevel, MIN(Comments) AS SampleComment, COUNT(DISTINCT Comments) AS Variants
FROM dbo.PerformanceReviews GROUP BY PerformanceLevel
ORDER BY CASE PerformanceLevel WHEN 'Needs Improvement' THEN 1 WHEN 'Meets Expectations' THEN 2 WHEN 'Exceeds Expectations' THEN 3 ELSE 4 END;

DROP TABLE #Tpl, #WD, #B, #Rv;
GO
