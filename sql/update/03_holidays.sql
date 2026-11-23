-- 03_holidays.sql: Finnish public holidays for every year of the period that has none yet (step 4 of sql/extend_data.sql)
-- The same 15 days a year as 05_seed_support_data.sql: New Year's Day, Epiphany, Good Friday, Easter Sunday, Easter Monday, May Day,
-- Ascension Day (Easter + 39), Pentecost (Easter + 49), Midsummer Eve (the Friday of 19-25 June), Midsummer Day, All Saints' Day
-- (the Saturday of 31 Oct - 6 Nov), Independence Day, Christmas Eve, Christmas Day, Boxing Day. Easter: the Gregorian computus.
-- Years that already have holidays are left alone. Needed before the hires, which fall on working days.
SET NOCOUNT ON;

;WITH y AS (
    SELECT YEAR(OldDate) AS Y FROM #Run
    UNION ALL SELECT Y + 1 FROM y WHERE Y < (SELECT YEAR(NewDate) FROM #Run) + 1      -- one more year: leave booked ahead and reviews
), c AS (
    SELECT y.Y, a = y.Y % 19, b = y.Y / 100, cc = y.Y % 100 FROM y
    WHERE NOT EXISTS (SELECT 1 FROM dbo.PublicHolidays h WHERE YEAR(h.HolidayDate) = y.Y)
), c2 AS (
    SELECT Y, a, b, cc, d = b / 4, e = b % 4, f = (b + 8) / 25 FROM c
), c3 AS (
    SELECT Y, a, b, cc, d, e, g = (b - f + 1) / 3 FROM c2
), c4 AS (
    SELECT Y, a, e, h = (19 * a + b - d - g + 15) % 30, i = cc / 4, k = cc % 4 FROM c3
), c5 AS (
    SELECT Y, a, h, l = (32 + 2 * e + 2 * i - h - k) % 7 FROM c4
), c6 AS (
    SELECT Y, h, l, m = (a + 11 * h + 22 * l) / 451 FROM c5
), ea AS (
    SELECT Y, EasterSunday = DATEFROMPARTS(Y, (h + l - 7 * m + 114) / 31, ((h + l - 7 * m + 114) % 31) + 1) FROM c6
), mid AS (
    SELECT Y, EasterSunday,
           MidsummerEve = DATEADD(DAY, (4 - DATEDIFF(DAY, '19000101', DATEFROMPARTS(Y, 6, 19)) % 7 + 7) % 7, DATEFROMPARTS(Y, 6, 19)),
           AllSaints    = DATEADD(DAY, (5 - DATEDIFF(DAY, '19000101', DATEFROMPARTS(Y, 10, 31)) % 7 + 7) % 7, DATEFROMPARTS(Y, 10, 31))
    FROM ea
)
INSERT dbo.PublicHolidays (HolidayDate, HolidayName)
SELECT v.D, v.N
FROM mid CROSS APPLY (VALUES
    (DATEFROMPARTS(Y, 1, 1),  N'New Year''s Day'),
    (DATEFROMPARTS(Y, 1, 6),  N'Epiphany'),
    (DATEADD(DAY, -2, EasterSunday), N'Good Friday'),
    (EasterSunday,            N'Easter Sunday'),
    (DATEADD(DAY, 1, EasterSunday),  N'Easter Monday'),
    (DATEFROMPARTS(Y, 5, 1),  N'May Day'),
    (DATEADD(DAY, 39, EasterSunday), N'Ascension Day'),
    (DATEADD(DAY, 49, EasterSunday), N'Pentecost'),
    (MidsummerEve,            N'Midsummer Eve'),
    (DATEADD(DAY, 1, MidsummerEve),  N'Midsummer Day'),
    (AllSaints,               N'All Saints'' Day'),
    (DATEFROMPARTS(Y, 12, 6), N'Independence Day'),
    (DATEFROMPARTS(Y, 12, 24), N'Christmas Eve'),
    (DATEFROMPARTS(Y, 12, 25), N'Christmas Day'),
    (DATEFROMPARTS(Y, 12, 26), N'Boxing Day')) v(D, N)
OPTION (MAXRECURSION 0);
