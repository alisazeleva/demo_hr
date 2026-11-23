-- 15_generate_2027_2030.sql: generates the data from 2026-11-17 to 2030-12-31, after scripts 01 to 14.
-- Scripts 06 to 11 build the company as it is on 2026-11-16 (its history derived backwards); this step moves forward from there,
-- date by date, and adds hires (at most 5 a year), promotions and transfers, pay changes, reviews, public holidays and leave.
-- The rows of scripts 06 to 11 stay as they are; the only change to them is filling the EndDate of an open job-history or
-- pay row when a newer row starts (90_finish.sql checks this). Deterministic: every run gives the same data.
-- The parts are in sql/15_generate_2027_2030/ and share temporary tables and one transaction, so they run only through this file.
-- Run once, from the repository root, in sqlcmd mode (the :r lines need sqlcmd), with quoted identifiers on (-I):
--   sqlcmd -S ".\SQLEXPRESS" -E -C -b -I -d DemoHR -f 65001 -i sql/15_generate_2027_2030.sql
-- (sql/build_all.sql runs it as part of the full build.) Any error stops the run and rolls everything back.
-- Steps: 1 check the period, 2 open the transaction and log the run, 3 public holidays, 4 set up the dates,
-- 5 add the records date by date (hires, promotions, transfers, pay), 6 reviews, 7 leave, 8 check everything and commit.
:on error exit

:r sql/15_generate_2027_2030/00_period.sql
GO
:r sql/15_generate_2027_2030/01_start.sql
GO
:r sql/15_generate_2027_2030/02_holidays.sql
GO
:r sql/15_generate_2027_2030/03_calendar.sql
GO
:r sql/15_generate_2027_2030/04_run_calendar.sql
GO
:r sql/15_generate_2027_2030/05_reviews.sql
GO
:r sql/15_generate_2027_2030/06_leave.sql
GO
:r sql/15_generate_2027_2030/90_finish.sql
GO
