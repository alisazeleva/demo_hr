-- build_all.sql: builds DemoHR from scratch with data up to 2030-12-31, in one run.
-- Creates the database, runs scripts 01 to 14 (first load: the company on 2026-11-16), extends the data with
-- sql/extend_data.sql (end date set there, 2030-12-31; it also makes a verified backup) and runs the full validation.
-- Deterministic: every build gives the same data as the database the report was made with.
-- It stops if the database already exists, so an existing database is never overwritten
-- (to rebuild, drop it first; to add data to an existing database, run sql/extend_data.sql instead).
-- Run from the repository root, in sqlcmd mode (the :r lines need sqlcmd), with quoted identifiers on (-I):
--   sqlcmd -S ".\SQLEXPRESS" -E -C -b -I -f 65001 -i sql/build_all.sql
-- Another database name: change the :setvar line below.
-- Takes a few minutes; the last result is the validation summary (every check must pass).
:setvar DbName DemoHR
:on error exit
SET NOCOUNT ON;

IF DB_ID(N'$(DbName)') IS NOT NULL
    THROW 50000, 'Database $(DbName) already exists. Drop it first to rebuild it, or run sql/extend_data.sql to add data to it.', 1;
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
PRINT '=== 13 extension tables';
:r sql/13_create_extension_tables.sql
GO
PRINT '=== 14 reporting views';
:r sql/14_create_reporting_views.sql
GO
PRINT '=== extend the data to 2030-12-31';
:r sql/extend_data.sql
GO
PRINT '=== full validation';
:r sql/99_full_validation.sql
GO
