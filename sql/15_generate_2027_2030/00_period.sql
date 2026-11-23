-- 00_period.sql: the period to generate (step 1 of sql/15_generate_2027_2030.sql). Read-only.
-- The data of scripts 06 to 11 describes the company on 2026-11-16; this step adds the records from 2026-11-17 to 2030-12-31.
-- Stops the whole run when scripts 01 to 14 have not run yet, or when the period has been generated already.
-- The period is kept in the session table #Run for the following steps.
SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.ReferenceDateLog', N'U') IS NULL OR OBJECT_ID(N'dbo.vw_DataRange', N'V') IS NULL
    THROW 50001, 'Run scripts 01 to 14 first (sql/build_all.sql runs everything in order).', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Employees)
    THROW 50002, 'There are no employees: run scripts 01 to 14 first (sql/build_all.sql runs everything in order).', 1;
IF EXISTS (SELECT 1 FROM dbo.ReferenceDateLog WHERE NewReferenceDate > '2026-11-16')
    THROW 50003, 'The data up to 2030-12-31 has been generated already. To start again, rebuild the database with sql/build_all.sql.', 1;

IF OBJECT_ID(N'tempdb..#Run') IS NOT NULL DROP TABLE #Run;
CREATE TABLE #Run (OldDate date NOT NULL, NewDate date NOT NULL);
INSERT #Run (OldDate, NewDate) VALUES ('2026-11-16', '2030-12-31');

SELECT OldDate AS DataUntil, NewDate AS GenerateUntil, DATEDIFF(DAY, OldDate, NewDate) AS DaysToAdd FROM #Run;
