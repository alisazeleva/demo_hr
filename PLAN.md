# DemoHR — Data Structure & Build Plan

Nov 16, 2026 · @Alisa

DemoHR holds 151 current employees on 2026-11-16 (a CEO plus 150 spread over five departments) in 10 SQL Server tables, filled by numbered scripts you run one at a time and then reported on in Power BI. The data is then extended to 2030-12-31 by adding records only (171 employees at the end; see Refreshing the data), and the report shows the company as of its refresh date.

## Decisions locked in

| Topic | Decision |
| --- | --- |
| Headcount | CEO sits under Acme Corporation, outside the departments: 150 in departments + 1 CEO = 151 employees |
| Employee numbers | EMP-000001 to EMP-000151 (the original plan said 150; the CEO is EMP-000001) |
| Department vs position | Every position belongs to one department; an employee's department always equals their position's department, so a transfer means a new position |
| Manager rule | A manager's job level must be strictly higher than every direct report's |
| Reference date | 2026-11-16 for the first load (scripts 06 to 11); the data is then extended to 2030-12-31 (`sql/extend_data.sql`), and the report's "today" is the refresh date, set in Power BI |
| Currency | EUR for everyone, annual salary |
| Leave days | Working days, excluding weekends and Finnish public holidays |
| Profile pictures | Generated in an external AI image tool, after the employee data is final; the database stores only filenames |
| Unchanged from your plan | One company, 5 departments, no subdepartments, no former employees, history tables for jobs and pay, one general job-history table for promotions and transfers |

Where a decision below is my default rather than yours, it is listed under Confirmed defaults at the end.

## Schema

Ten planned tables plus one small support table (PublicHolidays), in SQL Server, schema `dbo`, database `DemoHR`. Small fixed lists (change types, statuses, genders) are CHECK constraints rather than lookup tables; only LeaveTypes is a real table, as in your plan.

### OrganizationUnits

- `OrganizationUnitID` int identity, primary key
- `UnitName` nvarchar(100) not null, unique
- `UnitType` varchar(20) not null, CHECK in ('Company','Department')
- `ParentUnitID` int null, FK to OrganizationUnits (NULL for the company, the company's ID for each department)

### Positions

- `PositionID` int identity, primary key
- `PositionTitle` nvarchar(100) not null
- `JobFamily` nvarchar(50) not null
- `JobLevel` varchar(20) not null, CHECK in the 8 levels
- `JobLevelRank` tinyint not null, 1 = CEO up to 8 = Junior (lower number = more senior); CHECK 1 to 8
- `IsManagementPosition` bit not null
- `IsExecutivePosition` bit not null
- `OrganizationUnitID` int not null, FK; unique with PositionTitle

### Employees

- `EmployeeID` int identity, primary key (equals the number in EmployeeNumber)
- `EmployeeNumber` char(10) not null, unique, CHECK pattern `EMP-######`
- `FirstName`, `LastName` nvarchar(60) not null
- `Gender` varchar(10) not null, CHECK in ('Female','Male')
- `DateOfBirth` date not null
- `Nationality`, `NativeLanguage` nvarchar(60) not null
- `HireDate` date not null, CHECK later than DateOfBirth + 18 years (the old upper limit, the reference date, was removed by script 13)
- `EmailAddress` nvarchar(150) not null, unique
- `PositionID` int not null, FK
- `OrganizationUnitID` int not null, FK
- `ManagerEmployeeID` int null, FK to Employees, CHECK it differs from EmployeeID
- `ProfileImageFileName` varchar(20) null, unique; filled in the picture phase

### DepartmentWorkforcePlan

- `WorkforcePlanID` int identity, primary key
- `OrganizationUnitID` int not null, FK, unique (departments only)
- `TargetHeadcount` int not null, CHECK greater than 0

### EmployeeJobHistory

- `JobHistoryID` int identity, primary key
- `EmployeeID` int not null, FK
- `EffectiveDate` date not null; unique with EmployeeID
- `EndDate` date null, exclusive (the next record starts on that date); CHECK later than EffectiveDate
- `PositionID`, `OrganizationUnitID` int not null, FK
- `ManagerEmployeeID` int null, FK (NULL only for the CEO)
- `ChangeType` varchar(40) not null, CHECK in the 6 values from your plan
- `Reason` nvarchar(200) null
- Filtered unique index on EmployeeID WHERE EndDate IS NULL: one current record per employee

### EmployeeCompensationHistory

- `CompensationHistoryID` int identity, primary key
- `EmployeeID` int not null, FK
- `EffectiveDate` date not null; unique with EmployeeID
- `EndDate` date null, exclusive; CHECK later than EffectiveDate
- `BaseSalary` decimal(10,2) not null, CHECK greater than 0
- `Currency` char(3) not null, default and CHECK 'EUR'
- `PayFrequency` varchar(10) not null, default and CHECK 'Annual'
- `ChangeReason` varchar(40) not null, CHECK in ('Initial Salary','Annual Increase','Promotion','Department Transfer','Market Adjustment')
- Filtered unique index on EmployeeID WHERE EndDate IS NULL

### PerformanceReviews

- `PerformanceReviewID` int identity, primary key
- `EmployeeID`, `ReviewerEmployeeID` int not null, FK; CHECK they differ
- `ReviewDate`, `ReviewPeriodStart`, `ReviewPeriodEnd` date not null; CHECK start before end, end before review date
- `OverallRating` decimal(2,1) not null, CHECK 1.0 to 5.0
- `PerformanceLevel` varchar(30) not null, CHECK in the 4 levels
- `Comments` nvarchar(500) null
- Unique on EmployeeID + ReviewPeriodEnd

### LeaveTypes and EmployeeLeaves

- LeaveTypes: `LeaveTypeID` int identity primary key; `LeaveTypeName` nvarchar(50) unique; `IsPaid` bit
- EmployeeLeaves: `LeaveID` int identity primary key; `EmployeeID`, `LeaveTypeID` FK; `StartDate`, `EndDate` date, CHECK start not after end; `Status` varchar(10) CHECK in ('Approved','Pending','Rejected'); `ApprovedByEmployeeID` int null, FK (NULL only when Pending); `Notes` nvarchar(300) null

### DummyNames and PublicHolidays (support tables)

- DummyNames: `DummyNameID` int identity primary key; `NameType` varchar(5) ('First' or 'Last'); `NameValue` nvarchar(60); `Gender` varchar(10) null (first names only); `Nationality`, `NativeLanguage` nvarchar(60). Your plan listed FirstName and LastName as columns; two name types in one column lets each name be picked independently.
- PublicHolidays: `HolidayDate` date primary key; `HolidayName` nvarchar(60). Finnish holidays 2020 to 2027, used to count working days.

### Rules the database cannot enforce alone

These are checked by the validation scripts, because a foreign key or CHECK cannot express them:

- Employee department equals their position's department
- Current Employees row equals the open job-history row (position, department, manager)
- No circular reporting; manager level strictly higher than the report's
- No overlapping or gapped periods in job and compensation history
- Every leave and review falls after hire; no overlapping leaves for one employee

## Organization and positions

Six organization units (Acme Corporation plus the five departments) and 67 positions; each department is led by one C-Level executive who reports to the CEO.

### Headcount by department and level

| Level (rank) | Technology | Finance | Human Resources | Sales | Customer Experience | Total |
| --- | --- | --- | --- | --- | --- | --- |
| CEO (1) | under Acme Corporation |  |  |  |  | 1 |
| C-Level (2) | 1 | 1 | 1 | 1 | 1 | 5 |
| VP (3) | 2 | 0 | 0 | 1 | 0 | 3 |
| Director (4) | 3 | 2 | 1 | 2 | 2 | 10 |
| Manager (5) | 5 | 3 | 2 | 4 | 3 | 17 |
| Senior (6) | 10 | 6 | 4 | 8 | 5 | 33 |
| Professional (7) | 15 | 8 | 8 | 12 | 9 | 52 |
| Junior (8) | 9 | 5 | 4 | 7 | 5 | 30 |
| Department total | 45 | 25 | 20 | 35 | 25 | 150 |

The pyramid is deliberately small at the top: 17 managers lead 115 senior, professional and junior staff, about 6 to 8 per manager.

### Reporting lines

| Level | Reports to | Management flag | Executive flag |
| --- | --- | --- | --- |
| CEO | nobody | yes | yes |
| C-Level | CEO | yes | yes |
| VP | C-Level of the same department | yes | yes |
| Director | VP if the department has one, otherwise the C-Level | yes | no |
| Manager | a Director of the same department | yes | no |
| Senior, Professional, Junior | a Manager of the same department | no | no |

In Technology, VP Engineering leads the Software Engineering director; VP Data & IT leads the Data & Analytics and IT Operations directors. In Sales, VP Sales leads both directors. A transfer or promotion can change an employee's manager, so history can show other managers, but the current manager is always one level or more above the employee.

### Position catalogue (holders in brackets)

| Department | Level | Positions |
| --- | --- | --- |
| Acme Corporation | CEO | Chief Executive Officer (1) |
| Technology | C-Level | Chief Technology Officer (1) |
| Technology | VP | VP Engineering (1); VP Data & IT (1) |
| Technology | Director | Director of Software Engineering (1); Director of Data & Analytics (1); Director of IT Operations (1) |
| Technology | Manager | Engineering Manager (3); Data & Analytics Manager (1); IT Operations Manager (1) |
| Technology | Senior | Senior Software Engineer (6); Senior Data Analyst (2); Senior Systems Administrator (2) |
| Technology | Professional | Software Engineer (9); Data Analyst (3); Systems Administrator (3) |
| Technology | Junior | Junior Software Engineer (5); Junior Data Analyst (2); IT Support Specialist (2) |
| Finance | C-Level | Chief Financial Officer (1) |
| Finance | Director | Director of FP&A (1); Director of Accounting (1) |
| Finance | Manager | FP&A Manager (1); Accounting Manager (1); Treasury & Controls Manager (1) |
| Finance | Senior | Senior Financial Analyst (3); Senior Accountant (3) |
| Finance | Professional | Financial Analyst (4); Accountant (4) |
| Finance | Junior | Junior Financial Analyst (2); Junior Accountant (3) |
| Human Resources | C-Level | Chief Human Resources Officer (1) |
| Human Resources | Director | Director of People Operations (1) |
| Human Resources | Manager | Talent Acquisition Manager (1); HR Business Partner Manager (1) |
| Human Resources | Senior | Senior HR Business Partner (2); Senior Recruiter (2) |
| Human Resources | Professional | HR Business Partner (3); Recruiter (3); HR Specialist (2) |
| Human Resources | Junior | HR Assistant (2); Junior Recruiter (2) |
| Sales | C-Level | Chief Revenue Officer (1) |
| Sales | VP | VP Sales (1) |
| Sales | Director | Director of Enterprise Sales (1); Director of SMB & Partnerships (1) |
| Sales | Manager | Enterprise Sales Manager (2); SMB Sales Manager (1); Partnership Manager (1) |
| Sales | Senior | Senior Account Executive (6); Senior Sales Operations Analyst (2) |
| Sales | Professional | Account Executive (8); Sales Operations Analyst (2); Partnership Specialist (2) |
| Sales | Junior | Sales Development Representative (5); Junior Account Executive (2) |
| Customer Experience | C-Level | Chief Customer Officer (1) |
| Customer Experience | Director | Director of Customer Support (1); Director of Customer Success (1) |
| Customer Experience | Manager | Support Team Manager (2); Customer Success Team Manager (1) |
| Customer Experience | Senior | Senior Support Specialist (3); Senior Customer Success Specialist (2) |
| Customer Experience | Professional | Support Specialist (5); Customer Success Specialist (4) |
| Customer Experience | Junior | Junior Support Agent (3); Junior Customer Success Associate (2) |

The holder counts are the final headcount per position and add up to the matrix above. Employee numbers are assigned in rank order (CEO first, then C-Level, VP, and so on), so a manager's number is always lower than their reports'.

## Generation rules

The data is built backwards from a fixed final state, so the current headcount, positions and managers are exact by construction and the history is derived from them. Every random choice uses a fixed seed (a hash of seed value, employee ID and a label), so re-running a script gives identical data.

### Principles

- Final state first: set each employee's current position, department and manager, then generate hire date, job history, pay and reviews backwards from it.
- Rank order: people are generated from the top of the hierarchy down, so a manager's history always exists before their reports' history needs it.
- No stereotypes: position, level, pay, rating and promotion odds are drawn independently of gender and nationality.

### Names and demographics

- Nationalities (default, about 14): Finnish 40%, then Swedish, Estonian, German, Polish, British, French, Spanish, Italian, Indian, Turkish, Nigerian, Brazilian, Chinese and Vietnamese; none other above 10%.
- Native language follows nationality (for example Finnish, Swedish, German, Hindi, Turkish, Yoruba); about 5% of Finnish nationals have Swedish as native language.
- Names are drawn from DummyNames by nationality and gender, with accents kept in the name and removed in the email.
- Gender is about 50/50 overall and within every department and level group (within 10 percentage points).
- Age on 2026-11-16 by level: Junior 22–32, Professional 25–42, Senior 30–52, Manager 34–56, Director 40–58, VP 42–60, C-Level 44–62, CEO 50–58. Hire age is at least 21.
- Email: `firstname.lastname@acmecorp.example`; a duplicate gets `.2`, `.3` and so on.

### Hire dates

- Company founded 2012; hire dates fall between 2012-01-01 and 2026-09-30, on working days, weighted toward recent years (about 60% within the last 5 years).
- CEO and C-Level hired 2012–2014, VP and Directors 2012–2016, so every early hire had a valid manager above them. A hire date is redrawn if no eligible manager existed in the department on that date.

### Job history

- First record: EffectiveDate = HireDate, type Initial Assignment, in a position of the same rank as today or up to two ranks lower.
- Promotion means the rank number goes down by exactly 1, and never skips a level; a Department Transfer keeps the same rank; Promotion + Department Transfer does both on one date; Position Change is a same-rank move inside the department.
- Targets: about 30% of employees below Director have one promotion, 8% two, 10% a transfer, 4% a promotion with a transfer, 5% a position change, 12% a separate manager change. CEO has one record; C-Levels at most two.
- Events fall on the 1st of January, April, July or October, at least 18 months apart, at least 6 months after hire and before 2026-10-01.
- Every manager in the history is a current employee who was hired before that date and held a higher-ranked position on that date.
- The open record (EndDate NULL) equals the Employees row exactly; each EndDate equals the next EffectiveDate.

### Compensation

Current annual base salary comes from a level band, multiplied by a department factor (Technology 1.08, Finance 1.03, Sales 1.00, Human Resources 0.95, Customer Experience 0.93) and a fixed personal factor of 0.92 to 1.08.

| Level | Band, EUR per year |
| --- | --- |
| CEO | 280,000–340,000 (no department factor) |
| C-Level | 160,000–240,000 |
| VP | 125,000–165,000 |
| Director | 95,000–130,000 |
| Manager | 72,000–98,000 |
| Senior | 58,000–78,000 |
| Professional | 44,000–58,000 |
| Junior | 33,000–43,000 |

- History is built backwards: before a promotion the salary is current divided by 1.06–1.12; each 1 January an annual increase of 1.5–4.5% (average about 3%) applies to anyone employed at least 6 months.
- A Promotion or Promotion + Transfer salary change shares the job-history effective date and has reason Promotion; a plain transfer has reason Department Transfer (0–4%); about 5% of employees get one Market Adjustment of 4–8%.
- First record starts on HireDate with reason Initial Salary. Salaries are rounded to 100 EUR and never decrease.

### Performance reviews

- Annual review of each calendar year (period 1 January to 31 December), held on a working day between 20 January and 15 March of the next year. Latest reviews cover 2025; none for 2026 yet.
- Needs at least 6 months of service in the period (hired by 1 July); about 4% of eligible reviews are left out so some employees lack a recent review. "Recent" means a review in the last 12 months.
- Reviewer is the employee's manager on 31 December of the period, taken from job history. The CEO has no reviewer, so no review rows.
- Rating: personal baseline centered near 3.5, plus yearly variation, plus 0.3 in the year before a promotion; clipped to 1.0–5.0, one decimal.
- Level: below 2.5 Needs Improvement (about 4%), 2.5 to under 3.5 Meets Expectations (46%), 3.5 to under 4.5 Exceeds Expectations (46%), 4.5 or more Outstanding (4%).
- Comments are short templated sentences per level, with no personal or health details.

### Leave

- Window 2024-01-01 to 2027-03-31: past, current and booked leave. Start and end dates are always working days (no weekends or Finnish public holidays) and never precede hire; one employee's leaves never overlap.
- Vacation: 22–28 working days a year in 2–4 blocks, one of 10–15 days in June to mid-August. Past: 97% Approved, 3% Rejected. Booked for the future: 80% Approved, 20% Pending.
- Sick Leave: 0–5 episodes a year of 1–5 days (about 7 days a year on average), always Approved, never in the future.
- Parental Leave: about 4% of employees, one block of 30–120 working days, any gender. Unpaid Leave: about 2%, 5–20 days. Bereavement: about 3%, 1–3 days.
- ApprovedByEmployeeID is the employee's manager on the start date; the CEO's leave is approved by the CHRO; Pending leaves have NULL.
- At least 6 employees are on approved leave on 2026-11-16, so the currently-absent report is not empty.

## SQL script sequence

Fifteen numbered scripts, one logical step each; you run one, check its result, and only then do we move to the next. Scripts live as `.sql` files in your project folder and run in SSMS or with `sqlcmd -S <server> -d DemoHR -i <file>`. Generation scripts clear only their own tables inside a transaction, so each can be re-run safely and gives the same data.

| Script | What it does | Check before moving on |
| --- | --- | --- |
| 00\_create\_database | Creates database DemoHR | Database exists |
| 01\_create\_tables | All tables, keys, CHECKs, filtered unique indexes, empty | 11 tables, 0 rows |
| 02\_seed\_organization | Acme Corporation and 5 departments | 1 company, 5 departments |
| 03\_seed\_positions | The 67-position catalogue | Holders per department 45/25/20/35/25, plus 1 CEO |
| 04\_seed\_workforce\_plan | Five department targets | Targets sum to 155: Technology 48 and Sales 37 are above their headcount (45 and 35), so 2 of 5 departments are below target; the others equal their headcount |
| 05\_seed\_support\_data | DummyNames, PublicHolidays, LeaveTypes (5 types) | Enough names per nationality and gender |
| 06\_generate\_employees | 151 employees with final position, department, manager, demographics, email | 151 rows, headcount matches plan, unique numbers and emails |
| 07\_validate\_hierarchy | Read-only checks | One CEO, no cycles, no self-reports, manager level strictly higher |
| 08\_generate\_job\_history | Career history built backwards | Open record equals Employees row for all 151 |
| 09\_generate\_compensation | Salary history | One open record each, no overlaps, current salary in band |
| 10\_generate\_reviews | Annual reviews | Valid reviewers, ratings 1–5, dates after hire |
| 11\_generate\_leave | Leave records | No overlaps, valid approvers, 6 or more absent on 2026-11-16 |
| 12\_prepare\_profile\_images | Writes the list of employees with gender and age for image prompts; after you create the images, fills ProfileImageFileName | 151 unique filenames, one per EmployeeNumber |
| 13\_create\_extension\_tables | Add-only tables of the extension: ReferenceDateLog, DepartmentWorkforcePlanHistory, LeaveRequestInfo (first rows as of 2026-11-16) | Tables exist, one log row |
| 14\_create\_reporting\_views | Timeline views for Power BI (no reference date) and the as-of functions `fn_EmployeeAsOf`, `fn_OrgHierarchy`, `fn_EmployeeCurrent`, `fn_DepartmentHeadcountVsTarget` | Views return rows |
| extend\_data (with `sql/update/`) | Adds records from the end of the data to a new end date (2030-12-31): hires, job changes, pay, reviews, holidays, leave | Old rows unchanged, all rules hold |
| 99\_full\_validation | Every check from the final validation list, on the timeline and on a reference date (default the end of the data) | All checks pass |

Profile pictures stay the last data step, as in your plan: nothing is generated until the employee data is final. I will produce the prompt list (EmployeeNumber, gender, rough age, a style line identical for all), you create the images in your image tool and save them as `EMP-000001.jpg` to `EMP-000151.jpg`, then script 12 fills the column.

**Prepared workflow (nothing generated yet).** `images/prompts/sheet_01.txt` to `sheet_10.txt` hold ChatGPT prompts for 4 x 4 contact sheets of 16 people (sheet 10: 7 people and 9 empty cells), built from the employees of the first load (now `dbo.fn_EmployeeCurrent('2026-11-16')`) in EmployeeNumber order with a fixed seed (gender, age rounded to 5 on the reference date, nationality as appearance, one varied detail; no names). `images/sheet_map.csv` maps Sheet and Cell to EmployeeNumber. After the sheets are saved as `images/sheets/sheet_NN.png`, `python images/crop_sheets.py` cuts them into `images/profiles/EMP-######.jpg` (240 x 240, under 20 KB). Script 12 (`12_assign_profile_pictures.sql`) sets `ProfileImageFileName` to `EmployeeNumber.jpg` for all employees, including those whose picture does not exist yet.

## Refreshing the data

The first load (scripts 06 to 11) describes the company on 2026-11-16. It is extended forward by adding records, never by regenerating or shifting dates.

- **Rule for existing data.** Everything up to the old end of the data stays identical. The only edit to an old row is filling `EndDate` of an open job-history or pay row when a newer row starts. `Employees` rows are never updated: they hold each person as at hire (people of the first load: as on 2026-11-16), and the job history says what is true on any date.
- **Extend.** `sql/extend_data.sql` (set `EndDate` at the top; run from the repository root with `-I -f 65001`) makes a verified backup (last 10 kept), then in one transaction adds, in date order: hires (at most 5 a calendar year: department below target first, level Junior 45 %, Professional 40 %, Senior 15 %, manager of the same family with the smallest team), quarterly promotions and transfers with the 6- and 18-month rules, pay changes (promotion 6-12 %, transfer 0.2-4 %, 1 January increase 1.5-4.5 %, rare market adjustment 4-8 %), annual reviews (20 January to 15 March), Finnish public holidays, and leave (a yearly vacation plan, sick leave, bereavement, rare parental and unpaid leave) with request and decision dates in `LeaveRequestInfo`. It checks that no old row changed and that the rules hold, then commits. A run from A to C equals runs from A to B and B to C.
- **Power BI.** The reference date is the refresh date in Power BI, limited to the range of the data, so the report moves forward by itself and freezes at the end of the data (2030-12-31) until the data is extended again. Records dated after the reference date stay hidden until then; booked future leave is shown.
- **Validation after an extension.** Run script 99 (default: the state at the end of the data; set `@RefDate` at the top to check another date). Every check must pass.
- **Restore.** Every run prints the path of its backup; `RESTORE DATABASE DemoHR FROM DISK = N'<path>' WITH REPLACE` brings the database back.

## Power BI plan

Power BI Desktop (Windows) loads the reporting views in Import mode, and the report has a Home page and seven analysis pages that answer the reports listed in your plan. I write the views, the DAX measures, the Power Query steps and a colour theme; you build the visuals in Power BI Desktop following the page specs below. I cannot open Power BI Desktop myself, but I can try generating a Power BI Project (`.pbip`) folder with the model and measures already in it.

### Model

Star schema (built in Power BI Desktop; the views are in script 14). Table names use the `Dim` and `Fact` prefixes.

| Table | Source view | Notes |
| --- | --- | --- |
| DimEmployee | vw\_DimEmployee | One row per employee: person attributes, keys to position, department and manager, current salary and latest rating (org depth, manager chain and other unused columns are dropped in the model) |
| DimDepartment | vw\_DimDepartment | Five departments plus the company unit (Acme Corporation) |
| DimPosition | vw\_DimPosition | Title, job family, job level and rank, management flag |
| DimManager | vw\_DimManager | The manager role of an employee (employees with direct reports) |
| DimLeaveType | vw\_DimLeaveType | Leave types |
| DimDate | DAX CALENDAR | 2012-01-01 to 31 December of the year after the reference year, marked as the date table; `Years Before Reference` for year ranges in visual filters |
| FactJobHistory | vw\_JobHistory | Change type, keys and labels of the old and new position, department and manager |
| FactCompensation | vw\_CompensationHistory | Salary periods with the change percentage |
| FactReviews | vw\_PerformanceReviews | Rating, level, reviewer |
| FactLeaveDays | vw\_LeaveDays | One row per working day of an approved leave |
| FactLeaveRequests | vw\_LeaveRequests | One row per leave request of any status (pending, approved, rejected), with department on the start date |
| FactWorkforcePlan | vw\_FactWorkforcePlan | Target headcount per department |
| ReferenceDate | Power Query `ReferenceDateValue` | The single source of "today": the refresh date (or the `ReferenceDateOverride` parameter), limited to the range of the data in `vw_DataRange` |
| \_Measures | (DAX) | All measures |

The views hold the whole timeline without a reference date; each table query in Power Query keeps the state as of the reference date (people hired by then, the job, pay and review rows dated up to it, leave requests from their request date and Pending until decided, the latest workforce target). For SQL checks on one date use the functions `fn_EmployeeCurrent(@date)`, `fn_OrgHierarchy(@date)` and `fn_DepartmentHeadcountVsTarget(@date)`; the model does not load them.

DimEmployee relates one-to-many to every fact on EmployeeID; DimDepartment, DimPosition and DimManager filter DimEmployee (and DimDepartment filters FactWorkforcePlan); DimLeaveType filters FactLeaveDays; DimDate relates to each fact by its main date. There are no inactive relationships: every department, position and manager in the report is the employee's current one, and the job-history table carries the department, position and manager at the time of each event as text columns. Columns that no visual, measure, relationship or sort order uses are removed in the Power Query step of each table (see DESIGN.md).

### Measures

Headcount, Headcount vs Target, Average Salary, Average Salary at Year End, Employees at Year End, Average Annual Increase, Average Promotion Increase, Average Tenure (years), Promotions, Department Transfers, Average Months Before Promotion, Average Rating, Employees Without Recent Review, Leave Days, Vacation Days Used per Year, Currently Absent (on the reference date), Direct Reports and Span of Control.

### Report pages

| Page | Answers | Main visuals |
| --- | --- | --- |
| 0 Home | Index of the report: what each page answers, how to use the report | Header banner with headcount, departments and years of history, seven page cards with buttons, a how-to card |
| 1 Workforce | Total, by department, level, position, nationality, language, gender | Cards, bar charts, treemap, slicers |
| 2 Organization | Hierarchy, employees per manager, department vs target | Hierarchy or decomposition tree, bar chart of span of control, target gauge |
| 3 Career | Promotions, transfers, position and manager changes, months before promotion | Matrix of change type by year, bars by department, latest moves table, drill-through to profile |
| 4 Compensation | Salary by department and level, increases, promotion raises | Bar charts, combo of year-end headcount and average salary over time, clustered columns of increases, gender fairness bar |
| 5 Performance | Latest review, average rating, by department and manager, no recent review | Bar charts, rating distribution bars, heat matrix, latest-review table |
| 6 Leave | Days by employee, department and type, vacation usage, currently absent, pending requests | Stacked columns by month, matrix, Gantt chart of people absent now and approved absences in the next 30 days |
| 7 Employee profile | One person: picture placeholder, current role, salary and latest review, career timeline, salary history, reviews, leave | Hidden drill-through page on the employee name: header cards, tables, stepped line, charts |

### Profile pictures in Power BI

Power BI does not show images from a local file path, so the pictures are loaded into the model. A `ProfilePictures` table reads the JPEG files from the folder in the `ProfilePicturesFolder` parameter with `Folder.Files`, and adds a `Picture` column with `"data:image/jpeg;base64," & Binary.ToText([Content], BinaryEncoding.Base64)`; its data category is Image URL. It is a separate table, related many-to-one to `DimEmployee[ProfileImageFileName]` (the employee filters the picture), because merging the folder into the SQL query would trigger the Power Query privacy-level error. An employee without a file has no row. The photos are about 240 by 240 pixels and under 20 KB, so each data URI stays far below the 32,766 characters a model text cell can hold. The page 7 picture is the oval in the header with the measure `Profile Picture` (`SELECTEDVALUE(ProfilePictures[Picture])`, data category Image URL) as its image fill.

### Order of work

1. Views (script 14) and a connection check.
2. Model and relationships, then the measures.
3. Theme, then pages 1 to 6, then the profile page once pictures exist.

## Confirmed defaults

All nine open questions are answered; nothing is left to decide before scripts 00 and 01 are written.

- [x] SQL Server: default local instance, Windows login (`sqlcmd -E`)
- [x] Nationality mix: Finland-based, Finnish 40% plus other nationalities
- [x] Email domain: `acmecorp.example`
- [x] Employee numbers in rank order, CEO is EMP-000001
- [x] Salary bands and department factors as proposed
- [x] Gender values: Female and Male only
- [x] Support tables: DummyNames with NameType and NameValue, plus PublicHolidays
- [x] Time frames: founded 2012, hires to 2026-09-30, leave 2024-01-01 to 2027-03-31
- [x] Power BI: try a generated `.pbip` project
