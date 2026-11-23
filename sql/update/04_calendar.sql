-- 04_calendar.sql: set up the period (#Run.OldDate, #Run.NewDate] (step 5 of sql/extend_data.sql): the hire slots, the quarter starts
-- and the lists used by the hire and quarter steps. The records themselves are written by 05_run_calendar.sql, one date at a time in date
-- order, so a long run and several short runs give the same result. Runs inside the transaction opened by 02_log_run.sql.
--
-- Hire slots: at most 5 hires a calendar year. Each year has 5 fixed slots, one in each fifth of the year (70-day windows from 1 January,
--   73 days apart); the day inside the window comes from a hash of (seed, year, slot) and moves forward to a working day (no weekend, no
--   public holiday in dbo.PublicHolidays). A slot hires when its date falls in the period and the year still has room (hires already dated
--   that year plus the slots of this run stay within 5). The 22 hires dated 2026 fill that year, so the first slots are in 2027.
-- Quarter starts: 1 January, 1 April, 1 July, 1 October in the period (job and pay changes).
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Seed varchar(30) = 'demohr-update-v1';

CREATE TABLE #Slot (Seq int IDENTITY(1,1) PRIMARY KEY, SlotYear int NOT NULL, SlotNo int NOT NULL, SlotDate date NOT NULL);
;WITH y AS (
    SELECT YEAR(OldDate) AS Y FROM #Run
    UNION ALL SELECT Y + 1 FROM y WHERE Y < (SELECT YEAR(NewDate) FROM #Run)
), s AS (
    SELECT y.Y, k.K,
           Start = DATEADD(DAY, CAST(FLOOR(70 * ((CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@Seed, '|slot|', y.Y, '|', k.K)), 1, 4) AS int) & 2147483647) / 2147483648.0)) AS int),
                           DATEADD(DAY, (k.K - 1) * 73, DATEFROMPARTS(y.Y, 1, 1)))
    FROM y CROSS JOIN (VALUES (1),(2),(3),(4),(5)) k(K)
), d AS (
    SELECT s.Y, s.K,
           SlotDate = (SELECT TOP 1 x.D FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13),(14)) v(n)
                       CROSS APPLY (SELECT D = DATEADD(DAY, v.n, s.Start)) x
                       WHERE DATEDIFF(DAY, '19000101', x.D) % 7 < 5
                         AND NOT EXISTS (SELECT 1 FROM dbo.PublicHolidays h WHERE h.HolidayDate = x.D)
                       ORDER BY v.n)
    FROM s
), e AS (
    SELECT d.Y, d.K, d.SlotDate,
           Rnk = ROW_NUMBER() OVER (PARTITION BY d.Y ORDER BY d.SlotDate),
           HiredBefore = (SELECT COUNT(*) FROM dbo.Employees WHERE YEAR(HireDate) = d.Y)
    FROM d CROSS JOIN #Run r
    WHERE d.SlotDate > r.OldDate AND d.SlotDate <= r.NewDate
)
INSERT #Slot (SlotYear, SlotNo, SlotDate)
SELECT Y, K, SlotDate FROM e WHERE HiredBefore + Rnk <= 5 ORDER BY SlotDate
OPTION (MAXRECURSION 0);

-- reference lists (as in scripts 06 and 09)
CREATE TABLE #Quota (Ord int IDENTITY(1,1), Nationality nvarchar(60), Cnt int);
INSERT #Quota (Nationality, Cnt) VALUES
(N'Finnish',60),(N'Swedish',8),(N'Estonian',8),(N'German',8),(N'Polish',7),(N'British',7),(N'French',6),(N'Spanish',6),
(N'Italian',6),(N'Indian',8),(N'Turkish',6),(N'Nigerian',5),(N'Brazilian',6),(N'Chinese',6),(N'Vietnamese',4);
CREATE TABLE #StaffMap (Family nvarchar(50), MgrTitle nvarchar(100));
INSERT #StaffMap VALUES
(N'Engineering', N'Engineering Manager'), (N'Data & Analytics', N'Data & Analytics Manager'), (N'IT Operations', N'IT Operations Manager'),
(N'Financial Planning & Analysis', N'FP&A Manager'),
(N'Accounting', N'Accounting Manager'),(N'Accounting', N'Treasury & Controls Manager'),
(N'Talent Acquisition', N'Talent Acquisition Manager'), (N'HR Business Partnering', N'HR Business Partner Manager'),
(N'People Operations', N'Talent Acquisition Manager'),(N'People Operations', N'HR Business Partner Manager'),
(N'Enterprise Sales', N'Enterprise Sales Manager'),(N'Enterprise Sales', N'SMB Sales Manager'),
(N'Sales Operations', N'SMB Sales Manager'),(N'Sales Operations', N'Partnership Manager'),
(N'SMB & Partnerships', N'Partnership Manager'),
(N'Customer Support', N'Support Team Manager'), (N'Customer Success', N'Customer Success Team Manager');
CREATE TABLE #Band (JobLevel varchar(20) PRIMARY KEY, Mn decimal(10,2), Mx decimal(10,2));
INSERT #Band VALUES ('CEO',280000,340000),('C-Level',160000,240000),('VP',125000,165000),('Director',95000,130000),
                    ('Manager',72000,98000),('Senior',58000,78000),('Professional',44000,58000),('Junior',33000,43000);
CREATE TABLE #DF (UnitName nvarchar(100) PRIMARY KEY, F decimal(4,2));
INSERT #DF VALUES (N'Acme Corporation',1.00),(N'Technology',1.08),(N'Finance',1.03),(N'Human Resources',0.95),(N'Sales',1.00),(N'Customer Experience',0.93);
CREATE TABLE #Acc (Ch nvarchar(1) COLLATE Latin1_General_BIN2, Rep varchar(1));
INSERT #Acc VALUES
(N'ä','a'),(N'ö','o'),(N'å','a'),(N'ü','u'),(N'õ','o'),(N'é','e'),(N'è','e'),(N'ê','e'),(N'ë','e'),(N'á','a'),(N'à','a'),(N'â','a'),(N'ã','a'),
(N'í','i'),(N'ì','i'),(N'ó','o'),(N'ô','o'),(N'ú','u'),(N'ù','u'),(N'ç','c'),(N'ñ','n'),(N'ł','l'),(N'ś','s'),(N'ż','z'),(N'ź','z'),
(N'ć','c'),(N'ń','n'),(N'ę','e'),(N'ą','a'),(N'ı','i'),(N'ş','s'),(N'ğ','g'),(N'š','s'),(N'ž','z'),(N'đ','d'),
(N'ễ','e'),(N'ầ','a'),(N'ạ','a'),(N'ỳ','y'),(N'ũ','u'),(N'ơ','o'),(N'ư','u'),(N'ý','y');

CREATE TABLE #Hired (EmployeeID int, HireDate date);

-- the dates to process, in date order
CREATE TABLE #Cal (Seq int IDENTITY(1,1) PRIMARY KEY, D date NOT NULL UNIQUE, IsHire bit NOT NULL, IsQuarter bit NOT NULL);
;WITH q AS (
    SELECT DATEFROMPARTS(YEAR(OldDate), 1, 1) AS D FROM #Run
    UNION ALL SELECT DATEADD(MONTH, 3, D) FROM q WHERE D < (SELECT NewDate FROM #Run)
), alld AS (
    SELECT D FROM q WHERE D > (SELECT OldDate FROM #Run) AND D <= (SELECT NewDate FROM #Run)
    UNION SELECT SlotDate FROM #Slot
)
INSERT #Cal (D, IsHire, IsQuarter)
SELECT a.D, CASE WHEN EXISTS (SELECT 1 FROM #Slot s WHERE s.SlotDate = a.D) THEN 1 ELSE 0 END,
       CASE WHEN DAY(a.D) = 1 AND MONTH(a.D) IN (1,4,7,10) THEN 1 ELSE 0 END
FROM alld a ORDER BY a.D
OPTION (MAXRECURSION 0);
