-- 05_seed_support_data.sql: DummyNames, PublicHolidays (Finland 2012-2027) and LeaveTypes.
-- Run (UTF-8 file with accented names, so pass -f 65001):
--   sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -f 65001 -i sql/05_seed_support_data.sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
BEGIN TRANSACTION;

DELETE FROM dbo.DummyNames;
-- Restart IDs at 1 (a never-used identity needs seed 1, a used one needs 0)
DECLARE @seedNames int = CASE WHEN EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.DummyNames') AND last_value IS NULL) THEN 1 ELSE 0 END;
DBCC CHECKIDENT ('dbo.DummyNames', RESEED, @seedNames) WITH NO_INFOMSGS;
DELETE FROM dbo.PublicHolidays;
-- LeaveTypes is referenced by EmployeeLeaves; clear and reseed (fails if leaves already exist)
DELETE FROM dbo.LeaveTypes;
DECLARE @seedLeave int = CASE WHEN EXISTS (SELECT 1 FROM sys.identity_columns WHERE object_id = OBJECT_ID('dbo.LeaveTypes') AND last_value IS NULL) THEN 1 ELSE 0 END;
DBCC CHECKIDENT ('dbo.LeaveTypes', RESEED, @seedLeave) WITH NO_INFOMSGS;

-- ---------------------------------------------------------------- DummyNames
-- One row per list of names; split into individual rows below.
-- Native language follows nationality. The extra "Finnish / Swedish" block holds Finland-Swedish names
-- (Finnish nationality, Swedish native language) for the ~5% rule.
CREATE TABLE #Lists (Nationality nvarchar(60), NativeLanguage nvarchar(60), NameType varchar(5), Gender varchar(10) NULL, NameList nvarchar(max));

INSERT INTO #Lists (Nationality, NativeLanguage, NameType, Gender, NameList) VALUES
(N'Finnish', N'Finnish', 'First', 'Female', N'Aino,Helmi,Aada,Emilia,Sofia,Venla,Ella,Olivia,Siiri,Lilja,Katariina,Johanna,Maria,Anna,Laura,Minna,Sanna,Tiina,Heidi,Elina,Riikka,Kaisa,Pauliina,Marjatta,Hanna,Outi'),
(N'Finnish', N'Finnish', 'First', 'Male',   N'Eino,Onni,Elias,Leo,Oskari,Eetu,Juho,Mikko,Jari,Timo,Antti,Matti,Ville,Janne,Petri,Tuomas,Lauri,Jussi,Kalle,Henrik,Samuli,Teemu,Joonas,Aleksi,Markus,Ilkka'),
(N'Finnish', N'Finnish', 'Last',  NULL,     N'Korhonen,Virtanen,Mäkinen,Nieminen,Mäkelä,Hämäläinen,Laine,Heikkinen,Koskinen,Järvinen,Lehtonen,Lehtinen,Saarinen,Salminen,Heinonen,Niemi,Heikkilä,Kinnunen,Salonen,Turunen,Salo,Laitinen,Tuominen,Rantanen,Karjalainen,Jokinen,Mattila,Savolainen,Lahtinen,Ahonen,Kallio,Leppänen,Hirvonen,Peltonen,Miettinen,Väisänen'),
-- Finland-Swedish
(N'Finnish', N'Swedish', 'First', 'Female', N'Ingrid,Maja,Linnea,Annika,Karin,Elsa'),
(N'Finnish', N'Swedish', 'First', 'Male',   N'Anders,Erik,Johan,Nils,Mikael,Gustav'),
(N'Finnish', N'Swedish', 'Last',  NULL,     N'Lindqvist,Westerlund,Sjöberg,Holmström,Eklund,Nyström,Backman,Forsström'),
-- Swedish
(N'Swedish', N'Swedish', 'First', 'Female', N'Astrid,Alva,Ebba,Saga,Freja,Elin,Wilma,Klara,Sigrid,Matilda'),
(N'Swedish', N'Swedish', 'First', 'Male',   N'Lars,Oskar,Hugo,Axel,Viktor,Filip,Emil,Gunnar,Sven,Albin'),
(N'Swedish', N'Swedish', 'Last',  NULL,     N'Andersson,Johansson,Karlsson,Nilsson,Eriksson,Larsson,Olsson,Persson,Svensson,Gustafsson,Pettersson,Jonsson'),
-- Estonian
(N'Estonian', N'Estonian', 'First', 'Female', N'Kadri,Liis,Maarja,Triin,Kertu,Mari,Karin,Piret,Reet,Tiiu'),
(N'Estonian', N'Estonian', 'First', 'Male',   N'Taavi,Andres,Kristjan,Marko,Rein,Toomas,Mart,Jaan,Raivo,Siim'),
(N'Estonian', N'Estonian', 'Last',  NULL,     N'Tamm,Saar,Sepp,Mägi,Kask,Kukk,Rebane,Ilves,Pärn,Koppel,Oja,Lepik'),
-- German
(N'German', N'German', 'First', 'Female', N'Anna,Lena,Katharina,Sabine,Julia,Franziska,Greta,Heidi,Monika,Ursula'),
(N'German', N'German', 'First', 'Male',   N'Lukas,Jonas,Felix,Stefan,Matthias,Jürgen,Klaus,Tobias,Florian,Dieter'),
(N'German', N'German', 'Last',  NULL,     N'Müller,Schmidt,Schneider,Fischer,Weber,Meyer,Wagner,Becker,Hoffmann,Schäfer,Koch,Richter'),
-- Polish
(N'Polish', N'Polish', 'First', 'Female', N'Agnieszka,Katarzyna,Małgorzata,Zofia,Magdalena,Ewa,Joanna,Barbara,Aleksandra,Natalia'),
(N'Polish', N'Polish', 'First', 'Male',   N'Piotr,Krzysztof,Tomasz,Paweł,Marcin,Michał,Andrzej,Jakub,Łukasz,Wojciech'),
(N'Polish', N'Polish', 'Last',  NULL,     N'Nowak,Kowalski,Wiśniewski,Wójcik,Kowalczyk,Kamiński,Lewandowski,Zieliński,Szymański,Woźniak,Dąbrowski,Kozłowski'),
-- British
(N'British', N'English', 'First', 'Female', N'Emma,Charlotte,Olivia,Amelia,Hannah,Sophie,Rebecca,Eleanor,Harriet,Fiona'),
(N'British', N'English', 'First', 'Male',   N'Oliver,Harry,George,Thomas,James,William,Edward,Richard,Benjamin,Alistair'),
(N'British', N'English', 'Last',  NULL,     N'Smith,Jones,Taylor,Brown,Wilson,Evans,Thomas,Roberts,Walker,Wright,Thompson,Hughes'),
-- French
(N'French', N'French', 'First', 'Female', N'Camille,Léa,Chloé,Manon,Élodie,Margaux,Juliette,Océane,Sylvie,Isabelle'),
(N'French', N'French', 'First', 'Male',   N'Louis,Pierre,Antoine,Julien,Mathieu,Étienne,Hugo,Nicolas,Baptiste,Thierry'),
(N'French', N'French', 'Last',  NULL,     N'Martin,Bernard,Dubois,Petit,Durand,Leroy,Moreau,Lefèvre,Girard,Fournier,Lambert,Rousseau'),
-- Spanish
(N'Spanish', N'Spanish', 'First', 'Female', N'Lucía,María,Carmen,Paula,Elena,Marta,Alba,Sara,Pilar,Rocío'),
(N'Spanish', N'Spanish', 'First', 'Male',   N'Javier,Carlos,Miguel,Alejandro,Diego,Sergio,Pablo,Álvaro,Jorge,Raúl'),
(N'Spanish', N'Spanish', 'Last',  NULL,     N'García,Rodríguez,González,Fernández,López,Martínez,Sánchez,Pérez,Gómez,Ruiz,Hernández,Díaz'),
-- Italian
(N'Italian', N'Italian', 'First', 'Female', N'Giulia,Francesca,Chiara,Sofia,Martina,Valentina,Elisa,Alessia,Federica,Silvia'),
(N'Italian', N'Italian', 'First', 'Male',   N'Marco,Luca,Matteo,Giovanni,Andrea,Davide,Lorenzo,Stefano,Alessandro,Paolo'),
(N'Italian', N'Italian', 'Last',  NULL,     N'Rossi,Russo,Ferrari,Esposito,Bianchi,Romano,Colombo,Ricci,Marino,Greco,Bruno,Gallo'),
-- Indian
(N'Indian', N'Hindi', 'First', 'Female', N'Priya,Ananya,Kavita,Neha,Sunita,Deepa,Meera,Pooja,Lakshmi,Ritu'),
(N'Indian', N'Hindi', 'First', 'Male',   N'Arjun,Rahul,Vikram,Amit,Sanjay,Rohan,Anil,Karthik,Suresh,Nikhil'),
(N'Indian', N'Hindi', 'Last',  NULL,     N'Sharma,Patel,Singh,Kumar,Gupta,Reddy,Iyer,Nair,Mehta,Joshi,Rao,Desai'),
-- Turkish
(N'Turkish', N'Turkish', 'First', 'Female', N'Ayşe,Elif,Zeynep,Emine,Selin,Merve,Burcu,Esra,Deniz,Gül'),
(N'Turkish', N'Turkish', 'First', 'Male',   N'Mehmet,Mustafa,Ahmet,Emre,Burak,Can,Murat,Hakan,Serkan,Kemal'),
(N'Turkish', N'Turkish', 'Last',  NULL,     N'Yılmaz,Kaya,Demir,Şahin,Çelik,Yıldız,Aydın,Özdemir,Arslan,Doğan,Kılıç,Aslan'),
-- Nigerian
(N'Nigerian', N'Yoruba', 'First', 'Female', N'Adaeze,Chioma,Funmilayo,Ngozi,Folake,Temitope,Yetunde,Amaka,Bukola,Ifeoma'),
(N'Nigerian', N'Yoruba', 'First', 'Male',   N'Chinedu,Emeka,Oluwaseun,Tunde,Ikenna,Babatunde,Obinna,Femi,Kunle,Segun'),
(N'Nigerian', N'Yoruba', 'Last',  NULL,     N'Adeyemi,Okafor,Balogun,Okonkwo,Adebayo,Eze,Ogunleye,Nwosu,Abiola,Ibrahim,Olawale,Oyelaran'),
-- Brazilian
(N'Brazilian', N'Portuguese', 'First', 'Female', N'Ana,Beatriz,Camila,Fernanda,Juliana,Larissa,Mariana,Patrícia,Renata,Tatiana'),
(N'Brazilian', N'Portuguese', 'First', 'Male',   N'Lucas,Gabriel,Rafael,Thiago,Bruno,Felipe,Gustavo,Rodrigo,Eduardo,Leandro'),
(N'Brazilian', N'Portuguese', 'Last',  NULL,     N'Silva,Santos,Oliveira,Souza,Pereira,Costa,Rodrigues,Almeida,Nascimento,Lima,Araújo,Ribeiro'),
-- Chinese
(N'Chinese', N'Mandarin', 'First', 'Female', N'Mei,Hua,Xiu,Jing,Yan,Lan,Hui,Ling,Fang,Xin'),
(N'Chinese', N'Mandarin', 'First', 'Male',   N'Wei,Jun,Ming,Hao,Lei,Tao,Bo,Jian,Yong,Kai'),
(N'Chinese', N'Mandarin', 'Last',  NULL,     N'Wang,Li,Zhang,Liu,Chen,Yang,Huang,Zhao,Wu,Zhou,Xu,Sun'),
-- Vietnamese
(N'Vietnamese', N'Vietnamese', 'First', 'Female', N'Linh,Lan,Mai,Hoa,Thu,Huong,Ngoc,Trang,Thao,Anh'),
(N'Vietnamese', N'Vietnamese', 'First', 'Male',   N'Minh,Hung,Tuan,Duc,Long,Nam,Quang,Khoa,Dung,Hieu'),
(N'Vietnamese', N'Vietnamese', 'Last',  NULL,     N'Nguyễn,Trần,Lê,Phạm,Hoàng,Huỳnh,Phan,Vũ,Bùi,Ngô,Dương,Lý');

-- Ordered insert so DummyNameID is identical on every run
INSERT INTO dbo.DummyNames (NameType, NameValue, Gender, Nationality, NativeLanguage)
SELECT l.NameType, LTRIM(RTRIM(s.value)), l.Gender, l.Nationality, l.NativeLanguage
FROM #Lists l CROSS APPLY STRING_SPLIT(l.NameList, ',') s
ORDER BY l.Nationality, l.NativeLanguage, l.NameType, l.Gender, LTRIM(RTRIM(s.value));

DROP TABLE #Lists;

-- ------------------------------------------------------------ PublicHolidays
-- Finnish public holidays 2012-2027 (fixed dates plus Easter-based and weekday-based ones).
-- Range starts in 2012 (PLAN.md says 2020): hire dates from 2012 must land on working days.
;WITH Y AS (SELECT y FROM (VALUES (2012),(2013),(2014),(2015),(2016),(2017),(2018),(2019),(2020),(2021),(2022),(2023),(2024),(2025),(2026),(2027)) v(y)),
E AS (   -- Easter Sunday, Gregorian computus (integer arithmetic)
    SELECT y,
           a = y % 19, b = y / 100, c = y % 100
    FROM Y
), E2 AS (
    SELECT *, d = b / 4, e = b % 4, f = (b + 8) / 25 FROM E
), E3 AS (
    SELECT *, g = (b - f + 1) / 3 FROM E2
), E4 AS (
    SELECT *, h = (19 * a + b - d - g + 15) % 30, i = c / 4, k = c % 4 FROM E3
), E5 AS (
    SELECT *, l = (32 + 2 * e + 2 * i - h - k) % 7 FROM E4
), E6 AS (
    SELECT *, m = (a + 11 * h + 22 * l) / 451 FROM E5
), Easter AS (
    SELECT y, EasterSunday = DATEFROMPARTS(y, (h + l - 7 * m + 114) / 31, ((h + l - 7 * m + 114) % 31) + 1) FROM E6
), Anchors AS (   -- Midsummer Eve = Friday 19-25 June; All Saints' Day = Saturday 31 Oct - 6 Nov
    SELECT y, EasterSunday,
           MidsummerEve = DATEADD(DAY, (4 - (DATEDIFF(DAY, '19000101', DATEFROMPARTS(y, 6, 19)) % 7) + 7) % 7, DATEFROMPARTS(y, 6, 19)),
           AllSaints    = DATEADD(DAY, (5 - (DATEDIFF(DAY, '19000101', DATEFROMPARTS(y, 10, 31)) % 7) + 7) % 7, DATEFROMPARTS(y, 10, 31))
    FROM Easter   -- 1900-01-01 was a Monday, so remainder 0 = Monday ... 4 = Friday, 5 = Saturday
)
INSERT INTO dbo.PublicHolidays (HolidayDate, HolidayName)
SELECT HolidayDate, HolidayName
FROM Anchors
CROSS APPLY (VALUES
    (DATEFROMPARTS(y, 1, 1),            N'New Year''s Day'),
    (DATEFROMPARTS(y, 1, 6),            N'Epiphany'),
    (DATEADD(DAY, -2, EasterSunday),    N'Good Friday'),
    (EasterSunday,                      N'Easter Sunday'),
    (DATEADD(DAY, 1, EasterSunday),     N'Easter Monday'),
    (DATEFROMPARTS(y, 5, 1),            N'May Day'),
    (DATEADD(DAY, 39, EasterSunday),    N'Ascension Day'),
    (DATEADD(DAY, 49, EasterSunday),    N'Pentecost'),
    (MidsummerEve,                      N'Midsummer Eve'),
    (DATEADD(DAY, 1, MidsummerEve),     N'Midsummer Day'),
    (AllSaints,                         N'All Saints'' Day'),
    (DATEFROMPARTS(y, 12, 6),           N'Independence Day'),
    (DATEFROMPARTS(y, 12, 24),          N'Christmas Eve'),
    (DATEFROMPARTS(y, 12, 25),          N'Christmas Day'),
    (DATEFROMPARTS(y, 12, 26),          N'Boxing Day')
) h(HolidayDate, HolidayName);

-- ---------------------------------------------------------------- LeaveTypes
INSERT INTO dbo.LeaveTypes (LeaveTypeName, IsPaid) VALUES
(N'Vacation', 1), (N'Sick Leave', 1), (N'Parental Leave', 1), (N'Unpaid Leave', 0), (N'Bereavement', 1);

COMMIT TRANSACTION;
GO

-- Check 1: names per nationality and gender (first names) and last names; flag any below the minimum
SELECT Nationality,
       SUM(CASE WHEN NameType = 'First' AND Gender = 'Female' THEN 1 ELSE 0 END) AS FemaleFirst,
       SUM(CASE WHEN NameType = 'First' AND Gender = 'Male'   THEN 1 ELSE 0 END) AS MaleFirst,
       SUM(CASE WHEN NameType = 'Last' THEN 1 ELSE 0 END)                        AS LastNames,
       CASE WHEN SUM(CASE WHEN NameType = 'First' AND Gender = 'Female' THEN 1 ELSE 0 END) >= 10
             AND SUM(CASE WHEN NameType = 'First' AND Gender = 'Male'   THEN 1 ELSE 0 END) >= 10
             AND SUM(CASE WHEN NameType = 'Last' THEN 1 ELSE 0 END) >= 12 THEN 'OK' ELSE 'TOO FEW' END AS Status
FROM dbo.DummyNames GROUP BY Nationality ORDER BY Nationality;

-- Check 2: totals, duplicates, accents read correctly
SELECT COUNT(*) AS TotalNames,
       COUNT(DISTINCT Nationality) AS Nationalities,
       (SELECT COUNT(*) FROM (SELECT 1 AS x FROM dbo.DummyNames GROUP BY Nationality, NativeLanguage, NameType, Gender, NameValue HAVING COUNT(*) > 1) d) AS DuplicateRows
FROM dbo.DummyNames;
SELECT TOP 5 NameValue, Nationality FROM dbo.DummyNames WHERE NameValue LIKE N'%[äöåśłşğıčéèêü]%' ORDER BY DummyNameID;

-- Check 3: public holidays per year (expect 15 each) and spot checks
SELECT YEAR(HolidayDate) AS Yr, COUNT(*) AS Holidays FROM dbo.PublicHolidays GROUP BY YEAR(HolidayDate) ORDER BY Yr;
SELECT HolidayDate, DATENAME(WEEKDAY, HolidayDate) AS Weekday, HolidayName
FROM dbo.PublicHolidays WHERE HolidayDate BETWEEN '2026-01-01' AND '2026-12-31' ORDER BY HolidayDate;

-- Check 4: leave types
SELECT LeaveTypeID, LeaveTypeName, IsPaid FROM dbo.LeaveTypes ORDER BY LeaveTypeID;
GO
