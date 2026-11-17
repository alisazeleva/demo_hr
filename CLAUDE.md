# DemoHR: working rules for Claude Code

Build a dummy HR database (SQL Server) for Acme Corporation, then a Power BI report on top of it.

## Files in this folder

- `PLAN.md`: the authoritative data structure, generation rules and script sequence. If anything disagrees with another file, PLAN.md wins.
- `CONTEXT.md`: the original project description. Kept for background; superseded where PLAN.md says otherwise (see the note at its top).
- `sql/`: numbered scripts, one logical step each (`00_create_database.sql` ... `99_full_validation.sql`).
- `powerbi/`: Power BI project, DAX measures, theme (created later).

## Environment

- SQL Server Express, named instance .\SQLEXPRESS, Windows authentication.
- Run scripts with: `sqlcmd -S ".\SQLEXPRESS" -E -C -b -i sql/<file>.sql` (add `-d DemoHR` after script 00).
- Database name `DemoHR`, schema `dbo`.
- Never put passwords or connection secrets in files.

## Key decisions (details in PLAN.md)

- 151 employees: 1 CEO under Acme Corporation + 150 in 5 departments (Technology 45, Finance 25, Human Resources 20, Sales 35, Customer Experience 25).
- Employee numbers EMP-000001 to EMP-000151, assigned in rank order (CEO is EMP-000001).
- One company, 5 departments, no subdepartments. Current employees only: no former, terminated or retired employees.
- A position belongs to exactly one department; an employee's department always equals their position's department. A transfer means a new position.
- A manager's job level is strictly higher than every direct report's (JobLevelRank: 1 = CEO ... 8 = Junior).
- Reference date ("today") is 2026-11-16. Currency EUR, annual salary. Leave counted in working days, excluding weekends and Finnish public holidays.
- Gender values: Female and Male only. Email domain: `acmecorp.example`.
- Promotions and department transfers live in EmployeeJobHistory; pay changes live in EmployeeCompensationHistory. The current Employees row must always equal the open (EndDate IS NULL) job-history row.
- Profile pictures are created outside the database after the employee data is final; the database stores only `EMP-######.jpg` filenames.

## How to work

1. Do one script (or one logical step) at a time. Write it, run it, show the validation result, then stop and wait for my go-ahead.
2. Validate every stage before the next. If SQL fails, diagnose and fix the actual error. Do not silently change the schema to work around it; tell me and ask first.
3. Start from the empty database. Do not reuse anything from the abandoned 1,000-employee version.
4. Use transactions for destructive or rebuild steps. Generation scripts clear only their own tables, so they can be re-run.
5. Make generated data deterministic (fixed seed; hash of seed, employee ID and a label) so re-runs give identical data.
6. Generate the final state first, then derive history backwards from it (see PLAN.md, Generation rules).
7. Do not generate profile pictures until the employee dataset is finalized.
8. Do not add anything from the "not building" list: multiple companies, business units, subdepartments, former employees, termination or retirement records, recruitment, payroll, benefits, attendance, time tracking, training, expenses.
9. Keep answers short: what was done, the validation result, and the next step.
10. Power BI work follows DESIGN.md.
