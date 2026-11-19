-- 01_create_tables.sql: drops and recreates all 11 (empty) tables in DemoHR.
-- Run: sqlcmd -S ".\SQLEXPRESS" -E -C -b -d DemoHR -i sql/01_create_tables.sql
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON; -- required for filtered indexes; sqlcmd defaults to OFF
BEGIN TRANSACTION;

-- Drop in reverse dependency order so the script can be re-run
DROP TABLE IF EXISTS dbo.EmployeeLeaves;
DROP TABLE IF EXISTS dbo.PerformanceReviews;
DROP TABLE IF EXISTS dbo.EmployeeCompensationHistory;
DROP TABLE IF EXISTS dbo.EmployeeJobHistory;
DROP TABLE IF EXISTS dbo.Employees;
DROP TABLE IF EXISTS dbo.DepartmentWorkforcePlan;
DROP TABLE IF EXISTS dbo.Positions;
DROP TABLE IF EXISTS dbo.OrganizationUnits;
DROP TABLE IF EXISTS dbo.LeaveTypes;
DROP TABLE IF EXISTS dbo.DummyNames;
DROP TABLE IF EXISTS dbo.PublicHolidays;

CREATE TABLE dbo.OrganizationUnits (
    OrganizationUnitID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrganizationUnits PRIMARY KEY,
    UnitName           nvarchar(100) NOT NULL CONSTRAINT UQ_OrganizationUnits_UnitName UNIQUE,
    UnitType           varchar(20)   NOT NULL CONSTRAINT CK_OrganizationUnits_UnitType CHECK (UnitType IN ('Company','Department')),
    ParentUnitID       int NULL CONSTRAINT FK_OrganizationUnits_Parent REFERENCES dbo.OrganizationUnits (OrganizationUnitID)
);

CREATE TABLE dbo.Positions (
    PositionID             int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Positions PRIMARY KEY,
    PositionTitle          nvarchar(100) NOT NULL,
    JobFamily              nvarchar(50)  NOT NULL,
    JobLevel               varchar(20)   NOT NULL CONSTRAINT CK_Positions_JobLevel
        CHECK (JobLevel IN ('CEO','C-Level','VP','Director','Manager','Senior','Professional','Junior')),
    JobLevelRank           tinyint       NOT NULL CONSTRAINT CK_Positions_JobLevelRank CHECK (JobLevelRank BETWEEN 1 AND 8),
    IsManagementPosition   bit NOT NULL,
    IsExecutivePosition    bit NOT NULL,
    OrganizationUnitID     int NOT NULL CONSTRAINT FK_Positions_Unit REFERENCES dbo.OrganizationUnits (OrganizationUnitID),
    CONSTRAINT UQ_Positions_Title_Unit UNIQUE (PositionTitle, OrganizationUnitID)
);

CREATE TABLE dbo.Employees (
    EmployeeID           int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Employees PRIMARY KEY,
    EmployeeNumber       char(10)      NOT NULL CONSTRAINT UQ_Employees_Number UNIQUE
        CONSTRAINT CK_Employees_Number CHECK (EmployeeNumber LIKE 'EMP-[0-9][0-9][0-9][0-9][0-9][0-9]'),
    FirstName            nvarchar(60)  NOT NULL,
    LastName             nvarchar(60)  NOT NULL,
    Gender               varchar(10)   NOT NULL CONSTRAINT CK_Employees_Gender CHECK (Gender IN ('Female','Male')),
    DateOfBirth          date          NOT NULL,
    Nationality          nvarchar(60)  NOT NULL,
    NativeLanguage       nvarchar(60)  NOT NULL,
    HireDate             date          NOT NULL,
    EmailAddress         nvarchar(150) NOT NULL CONSTRAINT UQ_Employees_Email UNIQUE,
    PositionID           int NOT NULL CONSTRAINT FK_Employees_Position REFERENCES dbo.Positions (PositionID),
    OrganizationUnitID   int NOT NULL CONSTRAINT FK_Employees_Unit REFERENCES dbo.OrganizationUnits (OrganizationUnitID),
    ManagerEmployeeID    int NULL CONSTRAINT FK_Employees_Manager REFERENCES dbo.Employees (EmployeeID),
    ProfileImageFileName varchar(20) NULL,
    CONSTRAINT CK_Employees_NotOwnManager CHECK (ManagerEmployeeID IS NULL OR ManagerEmployeeID <> EmployeeID),
    CONSTRAINT CK_Employees_HireDate CHECK (HireDate > DATEADD(YEAR, 18, DateOfBirth) AND HireDate <= '2026-11-16')
);
-- Unique filename, but any number of NULLs until the picture phase
CREATE UNIQUE INDEX UX_Employees_ProfileImage ON dbo.Employees (ProfileImageFileName) WHERE ProfileImageFileName IS NOT NULL;

CREATE TABLE dbo.DepartmentWorkforcePlan (
    WorkforcePlanID    int IDENTITY(1,1) NOT NULL CONSTRAINT PK_DepartmentWorkforcePlan PRIMARY KEY,
    OrganizationUnitID int NOT NULL CONSTRAINT UQ_WorkforcePlan_Unit UNIQUE
        CONSTRAINT FK_WorkforcePlan_Unit REFERENCES dbo.OrganizationUnits (OrganizationUnitID),
    TargetHeadcount    int NOT NULL CONSTRAINT CK_WorkforcePlan_Target CHECK (TargetHeadcount > 0)
);

CREATE TABLE dbo.EmployeeJobHistory (
    JobHistoryID       int IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeJobHistory PRIMARY KEY,
    EmployeeID         int  NOT NULL CONSTRAINT FK_JobHistory_Employee REFERENCES dbo.Employees (EmployeeID),
    EffectiveDate      date NOT NULL,
    EndDate            date NULL,
    PositionID         int  NOT NULL CONSTRAINT FK_JobHistory_Position REFERENCES dbo.Positions (PositionID),
    OrganizationUnitID int  NOT NULL CONSTRAINT FK_JobHistory_Unit REFERENCES dbo.OrganizationUnits (OrganizationUnitID),
    ManagerEmployeeID  int  NULL CONSTRAINT FK_JobHistory_Manager REFERENCES dbo.Employees (EmployeeID),
    ChangeType         varchar(40) NOT NULL CONSTRAINT CK_JobHistory_ChangeType CHECK (ChangeType IN
        ('Initial Assignment','Promotion','Department Transfer','Promotion + Department Transfer','Position Change','Manager Change')),
    Reason             nvarchar(200) NULL,
    CONSTRAINT UQ_JobHistory_Employee_Effective UNIQUE (EmployeeID, EffectiveDate),
    CONSTRAINT CK_JobHistory_Dates CHECK (EndDate IS NULL OR EndDate > EffectiveDate)
);
CREATE UNIQUE INDEX UX_JobHistory_OneOpen ON dbo.EmployeeJobHistory (EmployeeID) WHERE EndDate IS NULL;

CREATE TABLE dbo.EmployeeCompensationHistory (
    CompensationHistoryID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeCompensationHistory PRIMARY KEY,
    EmployeeID    int  NOT NULL CONSTRAINT FK_CompHistory_Employee REFERENCES dbo.Employees (EmployeeID),
    EffectiveDate date NOT NULL,
    EndDate       date NULL,
    BaseSalary    decimal(10,2) NOT NULL CONSTRAINT CK_CompHistory_Salary CHECK (BaseSalary > 0),
    Currency      char(3)     NOT NULL CONSTRAINT DF_CompHistory_Currency DEFAULT 'EUR' CONSTRAINT CK_CompHistory_Currency CHECK (Currency = 'EUR'),
    PayFrequency  varchar(10) NOT NULL CONSTRAINT DF_CompHistory_PayFreq DEFAULT 'Annual' CONSTRAINT CK_CompHistory_PayFreq CHECK (PayFrequency = 'Annual'),
    ChangeReason  varchar(40) NOT NULL CONSTRAINT CK_CompHistory_Reason CHECK (ChangeReason IN
        ('Initial Salary','Annual Increase','Promotion','Department Transfer','Market Adjustment')),
    CONSTRAINT UQ_CompHistory_Employee_Effective UNIQUE (EmployeeID, EffectiveDate),
    CONSTRAINT CK_CompHistory_Dates CHECK (EndDate IS NULL OR EndDate > EffectiveDate)
);
CREATE UNIQUE INDEX UX_CompHistory_OneOpen ON dbo.EmployeeCompensationHistory (EmployeeID) WHERE EndDate IS NULL;

CREATE TABLE dbo.PerformanceReviews (
    PerformanceReviewID int IDENTITY(1,1) NOT NULL CONSTRAINT PK_PerformanceReviews PRIMARY KEY,
    EmployeeID          int NOT NULL CONSTRAINT FK_Reviews_Employee REFERENCES dbo.Employees (EmployeeID),
    ReviewerEmployeeID  int NOT NULL CONSTRAINT FK_Reviews_Reviewer REFERENCES dbo.Employees (EmployeeID),
    ReviewDate          date NOT NULL,
    ReviewPeriodStart   date NOT NULL,
    ReviewPeriodEnd     date NOT NULL,
    OverallRating       decimal(2,1) NOT NULL CONSTRAINT CK_Reviews_Rating CHECK (OverallRating BETWEEN 1.0 AND 5.0),
    PerformanceLevel    varchar(30) NOT NULL CONSTRAINT CK_Reviews_Level CHECK (PerformanceLevel IN
        ('Needs Improvement','Meets Expectations','Exceeds Expectations','Outstanding')),
    Comments            nvarchar(500) NULL,
    CONSTRAINT UQ_Reviews_Employee_PeriodEnd UNIQUE (EmployeeID, ReviewPeriodEnd),
    CONSTRAINT CK_Reviews_NotSelf CHECK (EmployeeID <> ReviewerEmployeeID),
    CONSTRAINT CK_Reviews_Dates CHECK (ReviewPeriodStart < ReviewPeriodEnd AND ReviewPeriodEnd < ReviewDate)
);

CREATE TABLE dbo.LeaveTypes (
    LeaveTypeID   int IDENTITY(1,1) NOT NULL CONSTRAINT PK_LeaveTypes PRIMARY KEY,
    LeaveTypeName nvarchar(50) NOT NULL CONSTRAINT UQ_LeaveTypes_Name UNIQUE,
    IsPaid        bit NOT NULL
);

CREATE TABLE dbo.EmployeeLeaves (
    LeaveID              int IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeLeaves PRIMARY KEY,
    EmployeeID           int NOT NULL CONSTRAINT FK_Leaves_Employee REFERENCES dbo.Employees (EmployeeID),
    LeaveTypeID          int NOT NULL CONSTRAINT FK_Leaves_Type REFERENCES dbo.LeaveTypes (LeaveTypeID),
    StartDate            date NOT NULL,
    EndDate              date NOT NULL,
    Status               varchar(10) NOT NULL CONSTRAINT CK_Leaves_Status CHECK (Status IN ('Approved','Pending','Rejected')),
    ApprovedByEmployeeID int NULL CONSTRAINT FK_Leaves_Approver REFERENCES dbo.Employees (EmployeeID),
    Notes                nvarchar(300) NULL,
    CONSTRAINT CK_Leaves_Dates CHECK (StartDate <= EndDate),
    -- approver is NULL exactly when the leave is Pending
    CONSTRAINT CK_Leaves_Approver CHECK ((Status = 'Pending' AND ApprovedByEmployeeID IS NULL)
                                      OR (Status <> 'Pending' AND ApprovedByEmployeeID IS NOT NULL))
);

CREATE TABLE dbo.DummyNames (
    DummyNameID    int IDENTITY(1,1) NOT NULL CONSTRAINT PK_DummyNames PRIMARY KEY,
    NameType       varchar(5)   NOT NULL CONSTRAINT CK_DummyNames_Type CHECK (NameType IN ('First','Last')),
    NameValue      nvarchar(60) NOT NULL,
    Gender         varchar(10)  NULL CONSTRAINT CK_DummyNames_Gender CHECK (Gender IN ('Female','Male')),
    Nationality    nvarchar(60) NOT NULL,
    NativeLanguage nvarchar(60) NOT NULL,
    -- first names carry a gender, last names do not
    CONSTRAINT CK_DummyNames_GenderByType CHECK ((NameType = 'First' AND Gender IS NOT NULL) OR (NameType = 'Last' AND Gender IS NULL))
);

CREATE TABLE dbo.PublicHolidays (
    HolidayDate date NOT NULL CONSTRAINT PK_PublicHolidays PRIMARY KEY,
    HolidayName nvarchar(60) NOT NULL
);

COMMIT TRANSACTION;
GO
