-- 00_check_dates.sql: decide the period to add (step 1 of sql/extend_data.sql). Read-only.
-- Old end of data = latest NewReferenceDate in dbo.ReferenceDateLog (2026-11-16 when the log does not exist yet);
-- new end of data = $(EndDate). Stops the whole run, before the backup, when there is nothing to add.
-- The result is kept in the session table #Run for the following steps.
SET NOCOUNT ON;

DECLARE @Old date = '2026-11-16';
IF OBJECT_ID(N'dbo.ReferenceDateLog', N'U') IS NOT NULL
    EXEC sp_executesql N'SELECT @o = MAX(NewReferenceDate) FROM dbo.ReferenceDateLog', N'@o date OUTPUT', @o = @Old OUTPUT;

IF OBJECT_ID(N'tempdb..#Run') IS NOT NULL DROP TABLE #Run;
CREATE TABLE #Run (OldDate date NOT NULL, NewDate date NOT NULL);
INSERT #Run (OldDate, NewDate) VALUES (@Old, CAST('$(EndDate)' AS date));

IF NOT EXISTS (SELECT 1 FROM #Run WHERE NewDate > OldDate)
BEGIN
    DECLARE @Msg nvarchar(200) = (SELECT N'Nothing to do: the data already runs to ' + CONVERT(nvarchar(10), OldDate, 23)
                                         + N', the new end date is ' + CONVERT(nvarchar(10), NewDate, 23) + N'.' FROM #Run);
    THROW 50001, @Msg, 1;
END;

SELECT OldDate AS OldEndOfData, NewDate AS NewEndOfData, DATEDIFF(DAY, OldDate, NewDate) AS DaysToAdd FROM #Run;
