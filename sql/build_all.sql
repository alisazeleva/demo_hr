-- build_all.sql: builds DemoHR from scratch with the full data set, 2012 to 2030-12-31, in one run.
-- Creates the database and runs every script in order: 01 to 12 build the company as it is on 2026-11-16 (with its history),
-- 13 and 14 add the timeline tables and the reporting views, 15 generates the data from 2026-11-17 to 2030-12-31,
-- and 99 validates everything. Deterministic: every build gives the same data.
-- It stops if the database already exists, so an existing database is never overwritten (to rebuild, drop it first).
-- Run from the repository root, in sqlcmd mode (the :r lines need sqlcmd), with quoted identifiers on (-I):
--   sqlcmd -S ".\SQLEXPRESS" -E -C -b -I -f 65001 -i sql/build_all.sql
-- Another database name: change the :setvar line below.
-- Takes under a minute; the last result is the validation summary (every check must pass).
:setvar DbName DemoHR
:on error exit
SET NOCOUNT ON;

IF DB_ID(N'$(DbName)') IS NOT NULL
    THROW 50000, 'Database $(DbName) already exists. Drop it first to rebuild it.', 1;
CREATE DATABASE [$(DbName)];
PRINT 'Database $(DbName) created.';
GO
USE [$(DbName)];
GO

PRINT '=== 01 tables';
:r sql/01_create_tables.sql
GO
PRINT '=== 02 organization';
:r sql/02_seed_organization.sql
GO
PRINT '=== 03 positions';
:r sql/03_seed_positions.sql
GO
PRINT '=== 04 workforce plan';
:r sql/04_seed_workforce_plan.sql
GO
PRINT '=== 05 support data';
:r sql/05_seed_support_data.sql
GO
PRINT '=== 06 employees';
:r sql/06_generate_employees.sql
GO
PRINT '=== 07 hierarchy checks';
:r sql/07_validate_hierarchy.sql
GO
PRINT '=== 08 job history';
:r sql/08_generate_job_history.sql
GO
PRINT '=== 09 compensation';
:r sql/09_generate_compensation.sql
GO
PRINT '=== 10 reviews';
:r sql/10_generate_reviews.sql
GO
PRINT '=== 11 leave';
:r sql/11_generate_leave.sql
GO
PRINT '=== 12 profile picture file names';
:r sql/12_assign_profile_pictures.sql
GO
PRINT '=== 13 timeline tables';
:r sql/13_create_timeline_tables.sql
GO
PRINT '=== 14 reporting views';
:r sql/14_create_reporting_views.sql
GO
PRINT '=== 15 data from 2026-11-17 to 2030-12-31';
:r sql/15_generate_2027_2030.sql
GO
PRINT '=== 99 full validation';
:r sql/99_full_validation.sql
GO
