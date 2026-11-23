-- extend_data.sql: add new records to DemoHR up to an end date (default 2030-12-31). Old records are kept as they are:
-- the only change to an old row is filling the EndDate of an open job-history or pay row when a newer row starts.
-- Run from the repository root, in sqlcmd mode (the :r lines need sqlcmd):
--   sqlcmd -S ".\SQLEXPRESS" -E -C -b -I -d DemoHR -f 65001 -i sql/extend_data.sql
-- Another end date (the run starts after the latest date in dbo.ReferenceDateLog):
--   sqlcmd ... -i sql/extend_data.sql   with the line ":setvar EndDate ..." below changed.
-- Steps: 1 check the period (stops when there is nothing to add), 2 back up the database (verified, last 10 kept),
-- 3 open one transaction, create the add-only tables, log the run, 4 public holidays, 5 add the new records date by date
-- (hires, promotions, transfers, pay), 6 reviews, 7 leave, and finally check everything and commit.
-- Any error stops the run and rolls the transaction back; restore the backup for anything else.
:setvar EndDate 2030-12-31
:on error exit

:r sql/update/00_check_dates.sql
GO
:r sql/update/01_backup.sql
GO
:r sql/update/02_log_run.sql
GO
:r sql/update/03_holidays.sql
GO
:r sql/update/04_calendar.sql
GO
:r sql/update/05_run_calendar.sql
GO
:r sql/update/06_reviews.sql
GO
:r sql/update/07_leave.sql
GO

:r sql/update/90_finish.sql
GO
