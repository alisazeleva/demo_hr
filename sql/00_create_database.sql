-- 00_create_database.sql: creates the DemoHR database if it does not exist.
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -i sql/00_create_database.sql
SET NOCOUNT ON;
IF DB_ID(N'DemoHR') IS NULL
BEGIN
    CREATE DATABASE DemoHR;
    PRINT 'Database DemoHR created.';
END
ELSE PRINT 'Database DemoHR already exists.';
GO
SELECT name AS DatabaseName, state_desc AS State FROM sys.databases WHERE name = N'DemoHR';
GO
