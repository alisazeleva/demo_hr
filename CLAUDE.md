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

Project `hr_dashboard.pbip` (PBIR report + TMDL model). Design rules and page layouts are in DESIGN.md; the model is described in PLAN.md (Power BI plan). Pages 1 to 7 are built and were adjusted by hand in Desktop, so treat them as the reference and never regenerate them over the user's changes: every `tools/build_*.py` is a first draft and would overwrite the hand edits (page 3 has a different layout and a matrix, pages 4 to 6 differ in colours, fonts and layout, page 7 has a redesigned header). DESIGN.md records each page as it is now, including positions. Page 7 is a hidden drill-through page filtered on `DimEmployee[FullName]`; drill-through works from any visual that contains the employee name.

### How to change things safely (Desktop is usually open)

1. **Model changes**: use the Power BI Modeling MCP server on the live Desktop session (find the port with `connection_operations ListLocalInstances`; it changes every time Desktop restarts). After the change, verify values with `dax_query_operations` against the same numbers from SQL.
2. **Save the model to disk**: `database_operations ExportToTmdlFolder` to a scratch folder, compare with `hr_dashboard.SemanticModel/definition`, and copy the changed table files (keep the original `database.tmdl`).
3. **Report changes**: edit the PBIR JSON under `hr_dashboard.Report/definition/pages/<id>/visuals/<id>/visual.json` directly, then run `python tools/validate_pbir.py` (must report 0 problems).
4. **Tell the user to close Desktop WITHOUT saving and reopen.** Saving first would overwrite the files edited on disk with Desktop's in-memory copy.
5. Do not touch pages the user built or adjusted by hand unless asked; copy their formatting (read the current visual.json) instead of the generator output.

`tools/`: `validate_pbir.py` (validates PBIR files against Microsoft's JSON schemas; needs `pip install jsonschema referencing`), `build_career.py` (generator for page 3, also a template for new pages), `build_comp.py`, `build_perf.py`, `build_leave.py` and `build_profile.py` (first drafts of pages 4 to 7; the hand-adjusted pages differ), `build_org.py` (historical template). When a new page is needed, copy the current hand-adjusted visual JSON of the nearest page (find visuals by type, not by position, because positions were changed by hand). Visual JSON that Desktop writes uses schema version 2.14.0, which is not downloadable, so the validator falls back to 2.13.0 and ignores the version string.

### Decisions and conventions

- **Star schema**: `DimEmployee`, `DimDepartment`, `DimPosition`, `DimManager`, `DimLeaveType`, `DimDate`; `FactJobHistory`, `FactCompensation`, `FactReviews`, `FactLeaveDays`, `FactLeaveRequests`, `FactWorkforcePlan`; helper tables `ReferenceDate` and `_Measures`. Use the attribute from its dimension only (for example `DimDepartment[Department]`, `DimPosition[JobLevel]`, `DimManager[ManagerName]`). Facts relate to DimEmployee and DimDate (active) and to the other dimensions through inactive relationships (USERELATIONSHIP for "at the time of the event").
- **Measure names**: Title Case noun phrases, units in the number format not the name, text measures prefixed `Text: ` in the Text folder, folders by page topic. Every measure has a description. Pending renames the user must do in Desktop (F2) because visuals use them: `Average Tenure (years)` to `Average Tenure`, `Largest Span of Control` to `Largest Team Size`.
- **Measures over a grouped column**: `CALCULATE(..., Table[Col] <> x)` replaces the visual's own filter on that column; use `KEEPFILTERS` (see `Career Events`).
- **Colouring bars by department** needs the department as the chart legend (Series), not a rule on a column of another table.
- **Workforce plan**: targets are Technology 48 and Sales 37 (others equal their headcount), so 2 departments are deliberately below target and `Departments at Target` is 3. Script 04 and the checks in 06 and 99 follow this.
- **Months before promotion** replaced "months between promotions": from the previous promotion, or from hire for a first promotion, to each promotion (so every department has a value).
- **Gender colours** are Female #E0A030 and Male #5B6472 (changed by hand; used on the page 1 donut and the page 4 gender chart).
- **Chart text** is 14 pt (data labels, axis labels, legends); tables and matrices use 14 pt values and 16 pt column headers; category labels on a few bars are 16 pt. Department bars on pages 4, 5 and 6 use one navy colour (theme colour 8); department colours stay on pages 1 and 3.
- **Slicers**: Department and Job level on every page 1 to 6 (synced on pages 2 to 6) plus one page-specific slicer (Nationality, Manager, Change type or Leave type). The profile page has an employee dropdown instead. Do not add header slicers to page 7.
- **Level labels**: `DimEmployee[Latest Level Short]` (NI, ME, EE, O) is shown in the page 5 table, `FactReviews[Level Long]` (for example "Meets Expectations (ME)") in the rating distribution chart, both sorted by `FactReviews[Level Order]` where sorting applies. `Latest Level in Selection` keeps `Level` and `Level Long` so the chart still cross-filters the table.
- **Profile text measures** read `DimPosition`, `DimDepartment` and `DimManager` with LOOKUPVALUE on keys in `DimEmployee`, because those dimensions filter `DimEmployee` and not the other way round.
- **Year-end measures** (`Average Salary at Year End`, `Employees at Year End`): the period filter must be inside AVERAGEX/COUNTROWS over FILTER within `CALCULATE(..., REMOVEFILTERS(DimDate))`; as a CALCULATE filter argument it is evaluated under the year filter and gives wrong numbers. Early years show only the first senior hires because there are no former employees; the page 4 chart says so.
- Theme: `powerbi/acme_hr_theme.json`, copied into the report's `StaticResources/RegisteredResources/`; keep both copies in sync. Tooltips 10 pt.

### Open items

- Profile pictures: script 12 was skipped, so the three picture checks in script 99 fail (46 of 49 pass). The info button next to the footer has no action yet, and page 7 shows initials in an oval until pictures exist.
- Page 3: the subtitle of "Career events by department" is still `Text: Months Before Promotion` (copied from the chart below it); replace it with a text that describes career events.
- Page 7: the "Current salary" and "Latest review" cards carry a leftover visual filter on `Text: Profile Tenure`; the measure `Text: Profile Role` has no description (every measure needs one).
- Slicers: the page 1 Department and Job level slicers are not in a sync group (pages 2 to 6 are); pages 3 to 6 keep a hidden leftover Manager slicer at x 1637; the Manager slicers of pages 2 and 5 share the sync group name "Nationality".
- Theme: `powerbi/acme_hr_theme.json` (20 and 16 pt) and the report's copy (20.25 and 17.25 pt, written by Desktop) are not identical; decide which one is the source and copy it over the other.
- Pending renames the user must do in Desktop (F2) because visuals use them (see Measure names): `Average Tenure (years)`, `Largest Span of Control`. `Vacation Days Used per Year` is really "per employee" and could be renamed with them.
- Career visuals count by the employee's current department (a version by department at the time of the event is possible).
- Page 5: `FactReviews[Level Order]` and page 6: `FactLeaveRequests[IsAbsentToday]` are calculated columns added through the MCP; press Refresh in Desktop after reopening if they show no data.
