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

## Power BI working notes

Project `hr_dashboard.pbip` (PBIR report + TMDL model). Design rules and page layouts are in DESIGN.md; the model is described in PLAN.md (Power BI plan). Pages 1 to 6 are built and were adjusted by hand in Desktop, so treat them as the reference and never regenerate them over the user's changes (`tools/build_comp.py` would overwrite page 4, which has since been changed by hand: the combo chart, colours and 14 pt fonts). Page 7 is an empty placeholder (page 7 also needs drill-through from pages 3 and later).

### How to change things safely (Desktop is usually open)

1. **Model changes**: use the Power BI Modeling MCP server on the live Desktop session (find the port with `connection_operations ListLocalInstances`; it changes every time Desktop restarts). After the change, verify values with `dax_query_operations` against the same numbers from SQL.
2. **Save the model to disk**: `database_operations ExportToTmdlFolder` to a scratch folder, compare with `hr_dashboard.SemanticModel/definition`, and copy the changed table files (keep the original `database.tmdl`).
3. **Report changes**: edit the PBIR JSON under `hr_dashboard.Report/definition/pages/<id>/visuals/<id>/visual.json` directly, then run `python tools/validate_pbir.py` (must report 0 problems).
4. **Tell the user to close Desktop WITHOUT saving and reopen.** Saving first would overwrite the files edited on disk with Desktop's in-memory copy.
5. Do not touch pages the user built or adjusted by hand unless asked; copy their formatting (read the current visual.json) instead of the generator output.

`tools/`: `validate_pbir.py` (validates PBIR files against Microsoft's JSON schemas; needs `pip install jsonschema referencing`), `build_career.py` (generator for page 3, also a template for new pages), `build_comp.py` (page 4 first draft; the hand-adjusted page differs), `build_leave.py` (page 6 first draft), `build_perf.py` (page 5 first draft; page 3 has since been reworked by hand, so it takes the matrix from page 2 and the table from page 3 without positions), `build_org.py` (historical template). Visual JSON that Desktop writes uses schema version 2.14.0, which is not downloadable, so the validator falls back to 2.13.0 and ignores the version string.

### Decisions and conventions

- **Star schema**: `DimEmployee`, `DimDepartment`, `DimPosition`, `DimManager`, `DimLeaveType`, `DimDate`; `FactJobHistory`, `FactCompensation`, `FactReviews`, `FactLeaveDays`, `FactLeaveRequests`, `FactWorkforcePlan`; helper tables `ReferenceDate` and `_Measures`. Use the attribute from its dimension only (for example `DimDepartment[Department]`, `DimPosition[JobLevel]`, `DimManager[ManagerName]`). Facts relate to DimEmployee and DimDate (active) and to the other dimensions through inactive relationships (USERELATIONSHIP for "at the time of the event").
- **Measure names**: Title Case noun phrases, units in the number format not the name, text measures prefixed `Text: ` in the Text folder, folders by page topic. Every measure has a description. Pending renames the user must do in Desktop (F2) because visuals use them: `Average Tenure (years)` to `Average Tenure`, `Largest Span of Control` to `Largest Team Size`.
- **Measures over a grouped column**: `CALCULATE(..., Table[Col] <> x)` replaces the visual's own filter on that column; use `KEEPFILTERS` (see `Career Events`).
- **Colouring bars by department** needs the department as the chart legend (Series), not a rule on a column of another table.
- **Workforce plan**: targets are Technology 48 and Sales 37 (others equal their headcount), so 2 departments are deliberately below target and `Departments at Target` is 3. Script 04 and the checks in 06 and 99 follow this.
- **Months before promotion** replaced "months between promotions": from the previous promotion, or from hire for a first promotion, to each promotion (so every department has a value).
- **Gender colours** are Female #E0A030 and Male #5B6472 (changed by hand; used on the page 1 donut and the page 4 gender chart).
- **Year-end measures** (`Average Salary at Year End`, `Employees at Year End`): the period filter must be inside AVERAGEX/COUNTROWS over FILTER within `CALCULATE(..., REMOVEFILTERS(DimDate))`; as a CALCULATE filter argument it is evaluated under the year filter and gives wrong numbers. Early years show only the first senior hires because there are no former employees; the page 4 chart says so.
- Theme: `powerbi/acme_hr_theme.json`, copied into the report's `StaticResources/RegisteredResources/`; keep both copies in sync. Tooltips 10 pt.

### Open items

- Page 7 (Employee profile) not built; follow DESIGN.md.
- Page 6: `FactLeaveRequests` (new view `vw_LeaveRequests` in script 13, run) was added through the MCP; its column `IsAbsentToday` is calculated, so press Refresh in Desktop after reopening if it shows no data. `build_leave.py` is the first draft; later hand edits win.
- Page 5: `FactReviews[Level Order]` was added through the MCP but could not be refreshed there (XMLA refresh error), so press Refresh in Desktop after reopening; the Top 10 manager filter was written by hand in JSON and should be checked in Desktop.
- Drill-through to the Employee profile page (from the career matrix and table, and others).
- Profile pictures: script 12 was skipped, so the three picture checks in script 99 fail (46 of 49 pass). The info button next to the footer has no action yet.
- The user's `Target Headcount` measure may still contain `RANDBETWEEN(0, 2)`, which makes target comparisons change on every refresh; suggest removing it.
- Career matrix counts by the employee's current department (a version by department at the time of the event is possible).
