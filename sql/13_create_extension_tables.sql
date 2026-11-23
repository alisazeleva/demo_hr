-- 13_create_extension_tables.sql: the add-only tables that belong to the data extension (sql/extend_data.sql) and the reporting views
-- Idempotent: run it after script 12 on a new database, or let sql/extend_data.sql run it on an existing one (inside its transaction).
-- Nothing in an existing table is edited here, except that the old upper limit on Employees.HireDate is removed.
--   dbo.ReferenceDateLog                one row per extension run: the end of the data after it (first row 2026-11-16, the date the first load was made for)
--   dbo.DepartmentWorkforcePlanHistory  the target headcount of a department from a date on (first rows: the plan of 2026-11-16)
--   dbo.LeaveRequestInfo                when a leave was requested and decided, its final status and approver (see 07_leave.sql)
-- Run (new database):  sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -i sql/13_create_extension_tables.sql
SET NOCOUNT ON;

-- Employees.HireDate had the reference date of the first generation as an upper limit; later hires need it gone
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Employees_HireDate' AND parent_object_id = OBJECT_ID(N'dbo.Employees')
           AND definition LIKE N'%2026-11-16%')
BEGIN
    ALTER TABLE dbo.Employees DROP CONSTRAINT CK_Employees_HireDate;
    ALTER TABLE dbo.Employees ADD CONSTRAINT CK_Employees_HireDate CHECK (HireDate > DATEADD(YEAR, 18, DateOfBirth));
END;

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
        IsNew                bit NOT NULL,            -- 1 = leave added by the extension, 0 = a Pending request of the first load
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
