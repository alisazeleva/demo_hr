-- 13_create_timeline_tables.sql: the tables for the data from 2026-11-17 to 2030-12-31 (filled by sql/15_generate_2027_2030.sql)
-- and their first rows, as of 2026-11-16. Run after script 12; idempotent (creates only what is missing).
--   dbo.ReferenceDateLog                the range of the data: first row 2026-11-16 (scripts 06 to 11), then 2030-12-31 (script 15); read by vw_DataRange
--   dbo.DepartmentWorkforcePlanHistory  the target headcount of a department from a date on (first rows: the plan of 2026-11-16)
--   dbo.LeaveRequestInfo                when a leave was requested and decided, its final status and approver (see 15_generate_2027_2030/06_leave.sql)
-- Run:  sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -i sql/13_create_timeline_tables.sql
SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.ReferenceDateLog', N'U') IS NULL
    CREATE TABLE dbo.ReferenceDateLog (
        RunID             int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ReferenceDateLog PRIMARY KEY,
        OldReferenceDate  date NULL,                                  -- NULL for the first row
        NewReferenceDate  date NOT NULL CONSTRAINT UQ_ReferenceDateLog_New UNIQUE,   -- the end of the data after this run
        RunAt             datetime2(0) NOT NULL CONSTRAINT DF_ReferenceDateLog_RunAt DEFAULT SYSDATETIME(),
        Note              nvarchar(200) NULL
    );

IF OBJECT_ID(N'dbo.DepartmentWorkforcePlanHistory', N'U') IS NULL
    CREATE TABLE dbo.DepartmentWorkforcePlanHistory (
        HistoryID          int IDENTITY(1,1) NOT NULL CONSTRAINT PK_DepartmentWorkforcePlanHistory PRIMARY KEY,
        OrganizationUnitID int NOT NULL CONSTRAINT FK_WorkforcePlanHistory_Unit REFERENCES dbo.OrganizationUnits (OrganizationUnitID),
        EffectiveDate      date NOT NULL,
        TargetHeadcount    int NOT NULL CONSTRAINT CK_WorkforcePlanHistory_Target CHECK (TargetHeadcount > 0),
        CONSTRAINT UQ_WorkforcePlanHistory UNIQUE (OrganizationUnitID, EffectiveDate)
    );

IF OBJECT_ID(N'dbo.LeaveRequestInfo', N'U') IS NULL
    CREATE TABLE dbo.LeaveRequestInfo (
        LeaveID              int NOT NULL CONSTRAINT PK_LeaveRequestInfo PRIMARY KEY CONSTRAINT FK_LeaveRequestInfo_Leave REFERENCES dbo.EmployeeLeaves (LeaveID),
        RequestDate          date NOT NULL,           -- the request exists (is visible) from this date
        DecisionDate         date NOT NULL,           -- until this date the request is Pending, then it has FinalStatus
        FinalStatus          varchar(10) NOT NULL CONSTRAINT CK_LeaveRequestInfo_Status CHECK (FinalStatus IN ('Approved','Rejected')),
        ApprovedByEmployeeID int NOT NULL CONSTRAINT FK_LeaveRequestInfo_Approver REFERENCES dbo.Employees (EmployeeID),
        IsNew                bit NOT NULL,            -- 1 = leave added by script 15, 0 = a Pending request of 2026-11-16 (script 11)
        CONSTRAINT CK_LeaveRequestInfo_Dates CHECK (DecisionDate >= RequestDate)
    );
GO

-- first rows (only when the tables are empty)
IF NOT EXISTS (SELECT 1 FROM dbo.ReferenceDateLog)
    INSERT dbo.ReferenceDateLog (OldReferenceDate, NewReferenceDate, Note) VALUES (NULL, '2026-11-16', N'Initial data generation (scripts 06 to 11)');
IF NOT EXISTS (SELECT 1 FROM dbo.DepartmentWorkforcePlanHistory)
    INSERT dbo.DepartmentWorkforcePlanHistory (OrganizationUnitID, EffectiveDate, TargetHeadcount)
    SELECT OrganizationUnitID, '2026-11-16', TargetHeadcount FROM dbo.DepartmentWorkforcePlan;
GO
