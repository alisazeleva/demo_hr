> NOTE (2026-11-16): This is the original project description, kept for background.
> PLAN.md supersedes it. Differences:
> - Headcount is 151, not 150: a CEO under Acme Corporation plus 150 employees in the 5 departments. Employee numbers run EMP-000001 to EMP-000151 (CEO is EMP-000001). The department targets (45/25/20/35/25 = 150) are unchanged.
> - Employee numbers are assigned in rank order, not hire order.
> - DummyNames uses NameType + NameValue (instead of FirstName/LastName columns); a PublicHolidays support table is added.
> - Decisions added: reference date 2026-11-16, EUR, working days excluding Finnish public holidays, position decides department, manager level strictly higher, Gender limited to Female/Male, email domain acmecorp.example.
> - Build sequence is now the 15 numbered scripts in PLAN.md, plus Power BI.
> Everything else below still applies.

DemoHR — Master Context / Project Plan 

Paste this entire document into a new chat whenever context is lost. 

 

1. Project objective 

We are building a DemoHR SQL Server database from scratch. 

The goal is a simple, realistic HR database for exactly 150 current employees. 

The previous 1,000-employee version has been abandoned. 

Critical rule 

We are starting completely from scratch. 

Do not reuse old employees, old IDs, old positions, old organization units, old workforce plans, or old generation procedures unless explicitly recreated in this plan. 

 

2. Company organization 

There is exactly one company: 

Acme Corporation 

It has exactly 5 departments: 

Technology 
Finance 
Human Resources 
Sales 
Customer Experience 

There are NO subdepartments. 

Final structure: 

Acme Corporation 
│ 
├── Technology 
├── Finance 
├── Human Resources 
├── Sales 
└── Customer Experience 

 

3. Workforce 

The database must contain exactly: 

150 current/active employees 

We do not need employees who: 

left the company  

retired  

were terminated  

are inactive  

The employee population represents the current workforce only. 

 

4. Workforce distribution 

Initial target: 

Department 

Target 

Technology 

45 

Finance 

25 

Human Resources 

20 

Sales 

35 

Customer Experience 

25 

TOTAL 

150 

 

5. Main tables 

The planned database contains: 

OrganizationUnits 
Positions 
Employees 
DepartmentWorkforcePlan 
 
EmployeeJobHistory 
EmployeeCompensationHistory 
 
PerformanceReviews 
 
LeaveTypes 
EmployeeLeaves 
 
DummyNames 

 

6. OrganizationUnits 

Stores the company and the 5 departments. 

Expected rows: 

Acme Corporation 
Technology 
Finance 
Human Resources 
Sales 
Customer Experience 

No subdepartment hierarchy. 

 

7. Positions 

Stores the job catalogue. 

Required concepts: 

CEO 
C-Level 
VP 
Director 
Manager 
Senior 
Professional 
Junior 

Positions should contain at least: 

PositionID 
PositionTitle 
JobFamily 
JobLevel 
JobLevelRank 
IsManagementPosition 
IsExecutivePosition 
OrganizationUnitID 

The position catalogue should be relatively small and realistic. 

Not every department needs every possible job level. 

 

8. Employees 

Employees represents current active employees only. 

Required fields: 

EmployeeID 
EmployeeNumber 
FirstName 
LastName 
Gender 
DateOfBirth 
Nationality 
NativeLanguage 
HireDate 
EmailAddress 
PositionID 
OrganizationUnitID 
ManagerEmployeeID 
ProfileImageFileName 

Employee numbers 

Exactly 150 employees: 

EMP-000001 
EMP-000002 
... 
EMP-000150 

Employee numbers must be unique. 

Employee demographics 

Each employee should have: 

realistic first name  

realistic last name  

gender  

date of birth  

nationality  

native language  

Nationality and native language should be realistic and diverse. 

Avoid creating stereotypes linking nationality/gender to particular jobs. 

 

9. Employee profile pictures 

Every employee should eventually have one professional profile picture. 

The image must correspond to the employee's gender. 

Images should be: 

professional corporate headshots  

realistic photographic style  

shoulders-up / head-and-shoulders framing  

diverse  

different people  

professional clothing  

consistent overall corporate photography style  

no celebrity likenesses  

Filename 

The filename must identify the employee. 

Recommended format: 

EMP-000001.jpg 
EMP-000002.jpg 
... 
EMP-000150.jpg 

The database field: 

ProfileImageFileName 

will contain the corresponding filename. 

Example: 

EmployeeNumber 

Gender 

ProfileImageFileName 

EMP-000001 

Female 

EMP-000001.jpg 

EMP-000002 

Male 

EMP-000002.jpg 

EMP-000003 

Female 

EMP-000003.jpg 

Important generation rule 

Do not generate 150 random pictures first and then try to match them. 

First generate the final 150 employee records. 

Then use each employee's: 

EmployeeNumber 
Gender 

to determine the corresponding profile picture. 

This prevents mismatches. 

Profile pictures should be generated later, after the employee dataset is finalized. 

 

10. Reporting structure 

Employees use: 

ManagerEmployeeID 

to represent the reporting hierarchy. 

Expected general structure: 

CEO 
│ 
├── Technology leadership 
│   └── Technology employees 
│ 
├── Finance leadership 
│   └── Finance employees 
│ 
├── HR leadership 
│   └── HR employees 
│ 
├── Sales leadership 
│   └── Sales employees 
│ 
└── Customer Experience leadership 
    └── Customer Experience employees 

Rules: 

CEO has no manager.  

Employees cannot report to themselves.  

No circular management relationships.  

Every other employee should have a valid manager.  

Managers should normally have a higher job level than their direct reports.  

 

11. DepartmentWorkforcePlan 

Stores department targets. 

Initial data: 

Technology              45 
Finance                 25 
Human Resources         20 
Sales                   35 
Customer Experience     25 

Total: 

150 

 

12. EmployeeJobHistory 

This is important. 

We need to know whether an employee: 

was promoted  

changed position  

moved departments  

changed manager  

Use one general job-history table rather than separate promotion and department-transfer tables. 

Suggested structure: 

EmployeeJobHistory 
------------------ 
JobHistoryID 
EmployeeID 
EffectiveDate 
EndDate 
PositionID 
OrganizationUnitID 
ManagerEmployeeID 
ChangeType 
Reason 

Possible ChangeType values: 

Initial Assignment 
Promotion 
Department Transfer 
Position Change 
Manager Change 
Promotion + Department Transfer 

Example 

Employee starts: 

2023-01-10 
Finance 
Financial Analyst 
Manager A 
Initial Assignment 

Later: 

2025-04-01 
Technology 
Software Engineer 
Manager B 
Department Transfer 

Later: 

2026-01-01 
Technology 
Senior Software Engineer 
Manager B 
Promotion 

This allows us to reconstruct the employee's complete career history. 

 

13. Important distinction: promotion vs transfer 

A promotion and department transfer are separate concepts. 

Example: 

Professional → Senior 

= Promotion 

Example: 

Finance → Technology 

= Department Transfer 

They can happen simultaneously: 

Finance / Financial Analyst 
        ↓ 
Technology / Senior Software Engineer 

with: 

ChangeType = Promotion + Department Transfer 

 

14. EmployeeCompensationHistory 

Every employee should have compensation history. 

Suggested structure: 

EmployeeCompensationHistory 
--------------------------- 
CompensationHistoryID 
EmployeeID 
EffectiveDate 
EndDate 
BaseSalary 
Currency 
PayFrequency 
ChangeReason 

Example: 

EMP-000042 
2023-01-01 
2024-01-01 
55000 
EUR 
Annual 
Initial Salary 

Then: 

EMP-000042 
2024-01-01 
2025-01-01 
59000 
EUR 
Annual 
Annual Increase 

Then: 

EMP-000042 
2025-01-01 
NULL 
65000 
EUR 
Annual 
Promotion 

The current salary record has: 

EndDate = NULL 

Rules 

Every employee should have a current compensation record.  

No overlapping compensation periods.  

Only one current compensation record per employee.  

Salary changes should be realistic.  

 

15. PerformanceReviews 

Stores historical performance reviews. 

Suggested structure: 

PerformanceReviews 
------------------ 
PerformanceReviewID 
EmployeeID 
ReviewerEmployeeID 
ReviewDate 
ReviewPeriodStart 
ReviewPeriodEnd 
OverallRating 
PerformanceLevel 
Comments 

Rating: 

1.0 - 5.0 

Possible performance levels: 

Needs Improvement 
Meets Expectations 
Exceeds Expectations 
Outstanding 

Employees can have multiple historical reviews. 

 

16. Leave system 

Two tables: 

LeaveTypes 
EmployeeLeaves 

LeaveTypes 

Example: 

Vacation 
Sick Leave 
Parental Leave 
Unpaid Leave 
Bereavement 

Fields: 

LeaveTypeID 
LeaveTypeName 
IsPaid 

EmployeeLeaves 

Suggested structure: 

LeaveID 
EmployeeID 
LeaveTypeID 
StartDate 
EndDate 
Status 
ApprovedByEmployeeID 
Notes 

Possible statuses: 

Approved 
Pending 
Rejected 

Generate realistic leave history for employees. 

 

17. DummyNames 

Support table used for generating realistic employee data. 

Possible fields: 

FirstName 
LastName 
Gender 
Nationality 
NativeLanguage 

This is a data-generation/support table, not a core HR entity. 

 

18. What we are NOT building 

Keep the project deliberately simple. 

Do not add unless explicitly requested: 

multiple companies  

multiple business units  

subdepartments  

former employees  

termination records  

retirement records  

recruitment  

payroll  

benefits  

attendance  

time tracking  

training  

expenses  

 

19. Build sequence 

We should work one logical step at a time and validate each step before continuing. 

Phase 1 — Database schema 

Create: 

OrganizationUnits 
Positions 
Employees 
DepartmentWorkforcePlan 
EmployeeJobHistory 
EmployeeCompensationHistory 
PerformanceReviews 
LeaveTypes 
EmployeeLeaves 
DummyNames 

Add appropriate: 

primary keys  

foreign keys  

unique constraints  

check constraints  

indexes  

 

Phase 2 — Organization 

Create: 

Acme Corporation 
Technology 
Finance 
Human Resources 
Sales 
Customer Experience 

Validate: 

1 company 
5 departments 

 

Phase 3 — Positions 

Create realistic positions for the 5 departments. 

Use: 

CEO 
C-Level 
VP 
Director 
Manager 
Senior 
Professional 
Junior 

as appropriate. 

Validate positions before creating employees. 

 

Phase 4 — Workforce plan 

Create the five department targets: 

Technology              45 
Finance                 25 
Human Resources         20 
Sales                   35 
Customer Experience     25 

Total = 150. 

 

Phase 5 — Employees 

Generate exactly: 

150 active employees 

Requirements: 

unique EmployeeNumber  

realistic names  

realistic gender  

nationality  

native language  

realistic birth dates  

realistic hire dates  

valid positions  

valid departments  

valid manager structure  

unique email addresses  

No former employees. 

 

Phase 6 — Management hierarchy 

Validate: 

exactly one CEO  

CEO has no manager  

everyone else has a manager  

no self-management  

no circular reporting  

managers have appropriate seniority  

all manager IDs are valid  

 

Phase 7 — Job history 

Generate realistic historical: 

initial assignments  

promotions  

department transfers  

position changes  

manager changes  

Make sure the final/current employee state matches the latest job-history record. 

 

Phase 8 — Compensation history 

Generate: 

initial salaries  

annual increases  

promotion increases  

current compensation  

Validate: 

no overlapping periods  

one current record per employee  

current record has EndDate = NULL  

 

Phase 9 — Performance reviews 

Generate realistic historical reviews. 

Validate: 

employee exists  

reviewer exists  

valid ratings  

sensible review dates  

multiple reviews where appropriate  

 

Phase 10 — Leave data 

Create leave types and employee leave records. 

Validate: 

valid employee  

valid leave type  

start date <= end date  

valid approval relationships  

realistic dates  

 

Phase 11 — Profile pictures 

After the employee dataset is finalized: 

Generate a profile-picture assignment for all 150 employees.  

Use the employee's actual gender.  

Make portraits diverse and professional.  

Name each picture using the employee number:  

EMP-000001.jpg 
... 
EMP-000150.jpg 

Populate:  

Employees.ProfileImageFileName 

Validate that every employee has exactly one corresponding image filename.  

 

20. Final validation 

At completion, verify: 

Employees 

Total employees = 150 
Active employees = 150 
Former employees = 0 

Employee numbers 

EMP-000001 → EMP-000150 

Departments 

Technology              45 
Finance                 25 
Human Resources         20 
Sales                   35 
Customer Experience     25 

Management 

Check: 

1 CEO 
No CEO manager 
No self-reporting 
No circular reporting 
No invalid manager IDs 

Job history 

Check: 

No invalid employees 
No invalid positions 
No invalid departments 
No contradictory current state 

Compensation 

Check: 

Every employee has current compensation 
Only one current compensation record 
No overlapping compensation periods 

Performance 

Check: 

Valid employee 
Valid reviewer 
Rating between 1 and 5 
Valid review dates 

Leave 

Check: 

Valid employee 
Valid leave type 
StartDate <= EndDate 
Valid approval relationship 

Pictures 

Check: 

150 employees 
150 picture filenames 
No duplicate filenames 
Every filename corresponds to EmployeeNumber 
Gender of picture matches employee record 

 

21. Useful reports we eventually want 

Workforce 

total employees  

employees by department  

employees by job level  

employees by position  

employees by nationality  

employees by native language  

employees by gender  

Organization 

organizational hierarchy  

employees per manager  

manager span of control  

department headcount  

department vs workforce target  

Career 

employee promotion history  

employees who changed departments  

employees who changed positions  

employees who changed managers  

complete employee career history  

average time between promotions  

Compensation 

current salary  

salary history  

average salary by department  

average salary by job level  

salary increases  

promotion-related salary changes  

Performance 

latest review  

average rating  

ratings by department  

ratings by manager  

employees without recent reviews  

Leave 

leave days by employee  

leave days by department  

leave by type  

currently absent employees  

annual vacation usage  

 

22. Important working rules 

When continuing this project: 

We are starting from an empty database.  

Do not use the old 1,000-employee data.  

Do not reuse old IDs or old organization structures.  

Do not create subdepartments.  

Do not create former/terminated/retired employees.  

Keep exactly 150 current employees.  

Use transactions for destructive/rebuild operations.  

Validate every stage before moving to the next.  

Give me one logical step at a time.  

If SQL fails, diagnose and fix the actual error.  

Don't silently change the schema to work around an error.  

Preserve all design decisions in this document.  

Don't generate profile pictures until the employee dataset is finalized.  

Profile-picture filenames must correspond to EmployeeNumber.  

Profile pictures must correspond to the employee's recorded gender.  

Promotions and department transfers must be represented in EmployeeJobHistory.  

Compensation must have historical records, not just a current salary.  

The current employee record must always agree with the latest applicable history.  

 

23. Current status 

We are starting from scratch. 

 