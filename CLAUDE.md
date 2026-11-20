# DemoHR: working rules for Claude Code

Build a dummy HR database (SQL Server) for Acme Corporation, then a Power BI report on top of it.

## Files in this folder

- `PLAN.md`: the authoritative data structure, generation rules and script sequence. If anything disagrees with another file, PLAN.md wins.
- `CONTEXT.md`: the original project description. Kept for background; superseded where PLAN.md says otherwise (see the note at its top).
- `sql/`: numbered scripts, one logical step each (`00_create_database.sql` ... `99_full_validation.sql`; `12_assign_profile_pictures.sql` sets `ProfileImageFileName` to `EmployeeNumber.jpg` for everyone).
- `hr_dashboard.pbip`, `hr_dashboard.Report/` (PBIR) and `hr_dashboard.SemanticModel/` (TMDL): the Power BI project. `DESIGN.md` has the design rules and page layouts.
- `powerbi/`: the report theme `acme_hr_theme.json`.
- `tools/`: Python helpers for the report (`validate_pbir.py` and first-draft page builders, see `tools/README.md`).
- `tests/`: repository checks and the measure tests (see Power BI working notes).
- `images/`: profile picture workflow (ChatGPT prompts, `sheet_map.csv`, `crop_sheets.py`); `desing/` (sic): PNG mockups of the pages.

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
7. Do not generate profile pictures until the employee dataset is finalized. The workflow is prepared in `images/` (prompts, map and crop script); the pictures themselves are made by hand in an image tool.
8. Do not add anything from the "not building" list: multiple companies, business units, subdepartments, former employees, termination or retirement records, recruitment, payroll, benefits, attendance, time tracking, training, expenses.
9. Keep answers short: what was done, the validation result, and the next step.
10. Power BI work follows DESIGN.md.

## Power BI working notes

Project `hr_dashboard.pbip` (PBIR report + TMDL model). Design rules and page layouts are in DESIGN.md; the model is described in PLAN.md (Power BI plan). The Home page (page 0, `tools/build_home.py`, first draft from the mockup in `desing/`) and pages 1 to 7 are built; pages 1 to 7 were adjusted by hand in Desktop, so treat them as the reference and never regenerate them over the user's changes: every `tools/build_*.py` is a first draft and would overwrite the hand edits (page 3 has a different layout and a matrix, pages 4 to 6 differ in colours, fonts and layout, page 7 has a redesigned header). DESIGN.md records each page as it is now, including positions. Page 7 is a hidden drill-through page filtered on `DimEmployee[FullName]`; drill-through works from any visual that contains the employee name.

### How to change things safely (Desktop is usually open)

1. **Model changes**: use the Power BI Modeling MCP server on the live Desktop session (find the port with `connection_operations ListLocalInstances`; it changes every time Desktop restarts). After the change, verify values with `dax_query_operations` against the same numbers from SQL.
2. **Save the model to disk**: `database_operations ExportToTmdlFolder` to a scratch folder, compare with `hr_dashboard.SemanticModel/definition`, and copy the changed table files (keep the original `database.tmdl`).
3. **Report changes**: edit the PBIR JSON under `hr_dashboard.Report/definition/pages/<id>/visuals/<id>/visual.json` directly, then run `python tools/validate_pbir.py` (must report 0 problems).
4. **Tell the user to close Desktop WITHOUT saving and reopen.** Saving first would overwrite the files edited on disk with Desktop's in-memory copy.
5. Do not touch pages the user built or adjusted by hand unless asked; copy their formatting (read the current visual.json) instead of the generator output.

`tools/`: `validate_pbir.py` (validates PBIR files against Microsoft's JSON schemas; needs `pip install jsonschema referencing`), `build_career.py` (generator for page 3, also a template for new pages), `build_comp.py`, `build_perf.py`, `build_leave.py` and `build_profile.py` (first drafts of pages 4 to 7; the hand-adjusted pages differ), `build_org.py` (historical template). When a new page is needed, copy the current hand-adjusted visual JSON of the nearest page (find visuals by type, not by position, because positions were changed by hand). Visual JSON that Desktop writes uses schema version 2.14.0, which is not downloadable, so the validator falls back to 2.13.0 and ignores the version string.

### Decisions and conventions

- **Star schema**: `DimEmployee`, `DimDepartment`, `DimPosition`, `DimManager`, `DimLeaveType`, `DimDate`; `FactJobHistory`, `FactCompensation`, `FactReviews`, `FactLeaveDays`, `FactLeaveRequests`, `FactWorkforcePlan`; helper tables `ReferenceDate` and `_Measures`. Use the attribute from its dimension only (for example `DimDepartment[Department]`, `DimPosition[JobLevel]`, `DimManager[ManagerName]`). Facts relate to DimEmployee and DimDate (active); there are no inactive relationships, so department, position and manager are the employee's current ones (job history keeps the labels at the time of the event). Only columns that something uses are in the model: unused source columns are removed in each table's `Slim` step (`Table.RemoveColumns(..., MissingField.Ignore)`) and the list of what was dropped is in DESIGN.md; do not add a column to a table without a use, and keep `DimEmployee[ProfileImageFileName]` for the page 7 pictures.
- **Measure names**: Title Case noun phrases, units in the number format not the name, text measures prefixed `Text: ` in the Text folder, folders by page topic. Every measure has a description. Pending renames the user must do in Desktop (F2) because visuals use them: `Average Tenure (years)` to `Average Tenure`, `Largest Span of Control` to `Largest Team Size`.
- **Measure style**: formulas are formatted over several lines with 4-space indentation, `VAR` names in camelCase, `//` comments for every non-trivial measure (what it counts, why a filter is placed where it is), and a `///` description on every measure; each measure is in a display folder. Unused measures are removed (`Hires`, `Female Share` and `Vacation Days Used per Employee` were deleted on 2026-11-19); a measure referenced by a visual, a visual filter, conditional formatting or another measure counts as used. `Headcount vs Target` is target minus headcount (positive = below target).
- **Tests** (`tests/`): `python -m pytest tests -q` (needs `pip install -r tests/requirements.txt`) checks the files without Desktop: PBIR schemas (`tools/validate_pbir.py`), measure descriptions, folders and comments, unused measures, fields used by visuals and DAX that exist in the model, bookmarks, button links and page order, the Info ON/OFF bookmarks on every page, that the report opens on the Home page (Desktop saves whichever page was showing as the active page), no saved filter selections (a chosen slicer, filter-pane or drill-through value, for example an employee name, is stored in the report files by Desktop and goes to git; excluding a value is fine; clear selections before saving, or list a deliberate default in `ALLOWED_SELECTIONS` in `tests/test_repo.py`), and no personal paths, emails or secrets in tracked files. `tests/measures.dax` has the expected numbers from SQL; run it against the open model (Desktop DAX query view or the MCP `dax_query_operations`) after model changes and expect no `FAIL` row. Run both before a commit.
- **Removing a model column**: delete it with the MCP and add its name to the table's `Slim` list in the same change (otherwise the next refresh may bring it back), refresh the table, and re-run the checks; a calculated table such as `DimDate` is changed by editing its expression.
- **Measures over a grouped column**: `CALCULATE(..., Table[Col] <> x)` replaces the visual's own filter on that column; use `KEEPFILTERS` (see `Career Events`).
- **Colouring bars by department** needs the department as the chart legend (Series), not a rule on a column of another table.
- **Workforce plan**: targets are Technology 48 and Sales 37 (others equal their headcount), so 2 departments are deliberately below target and `Departments at Target` is 3. Script 04 and the checks in 06 and 99 follow this.
- **Months before promotion** replaced "months between promotions": from the previous promotion, or from hire for a first promotion, to each promotion (so every department has a value).
- **Gender colours** are Female #E0A030 and Male #5B6472 (changed by hand; used on the page 1 donut and the page 4 gender chart).
- **Chart text** is 14 pt (data labels, axis labels, legends); tables and matrices use 14 pt values and 16 pt column headers; category labels on a few bars are 16 pt. Department bars on pages 4, 5 and 6 use one navy colour (theme colour 8); department colours stay on pages 1 and 3.
- **Slicers**: Department and Job level on every page 1 to 6 (synced across all of them) plus one page-specific slicer (Nationality, Manager, Change type or Leave type). The profile page has an employee dropdown instead. Do not add header slicers to page 7.
- **Level labels**: `DimEmployee[Latest Level Short]` (NI, ME, EE, O) is shown in the page 5 table, `FactReviews[Level Long]` (for example "Meets Expectations (ME)") in the rating distribution chart, both sorted by `FactReviews[Level Order]` where sorting applies. `Latest Level in Selection` keeps `Level` and `Level Long` so the chart still cross-filters the table.
- **Profile text measures** read `DimPosition`, `DimDepartment` and `DimManager` with LOOKUPVALUE on keys in `DimEmployee`, because those dimensions filter `DimEmployee` and not the other way round.
- **Year-end measures** (`Average Salary at Year End`, `Employees at Year End`): the period filter must be inside AVERAGEX/COUNTROWS over FILTER within `CALCULATE(..., REMOVEFILTERS(DimDate))`; as a CALCULATE filter argument it is evaluated under the year filter and gives wrong numbers. Early years show only the first senior hires because there are no former employees; the page 4 chart says so.
- Theme: `powerbi/acme_hr_theme.json`, copied into the report's `StaticResources/RegisteredResources/`; keep both copies identical (they are; the sizes are Desktop's 20.25 and 17.25 pt). Every visible visual title and subtitle also carries an explicit size (20 and 16 pt), so the theme no longer decides it. Tooltips 10 pt.
- **Home page** (page 0, first page, the page the report opens on; no slicers): header banner with three figures (`Headcount`, `Departments`, `Years of History`), seven page cards with navigation buttons, a "Using the report" card (`Text: Home Data Note`). The page navigator on every page hides it (`showPage` off for Home in the navigator's `pages` object) and shows hidden pages, so the Employee profile page is listed. The navigator sits at (22, 216.5), 253 x 556 on every page.
- **Info pop-up** on every page (Home and the profile page included): the info button in the left menu opens the bookmark `<Page> Info ON`, which shows a hidden navy panel with `Text: Info Note` (the data is fictional, figures as of the reference date) and a hidden close button linked to `<Page> Info OFF`. The bookmarks act only on those three visuals (`targetVisualNames`), with data and filter state off, and must not contain `preserveNewVisualVisibility` (the schema rejects it). The tests check that every page has the pair and a working button.
- **Absent today chart** (page 6, Gantt): shows approved absences in progress on the reference date plus those that start within 30 days (`Absence Window End Date` = reference date + 30, `FactLeaveRequests[IsInAbsenceWindow]` as the visual filter); the tooltip shows `Days Left in Absence` (in progress: days left after the reference date; not started: full length; calendar days).

### Open items

- Profile pictures (proof of concept with sheet 1, employees EMP-000001 to EMP-000016): script 12 has run, so all 49 checks in script 99 pass. The model has a `ProfilePictures` table (Power Query reads the JPEGs from the `ProfilePicturesFolder` parameter in `expressions.tmdl`, turns each into a base64 data URI, columns `FileName` and `Picture` with data category Image URL, both hidden), related many-to-one to `DimEmployee[ProfileImageFileName]` so the selected employee filters it. An employee without a file has no row. On page 7 the oval in the header uses the measure `Profile Picture` (`SELECTEDVALUE(ProfilePictures[Picture])`, data category Image URL) as its image fill, so the picture is clipped to the circle; there are no initials any more (`Text: Profile Initials` was deleted on 2026-11-20). `ProfilePicturesFolder` is `C:\DemoHR\profiles`, a folder outside the repo and the user profile so that no personal path is committed (the privacy test fails on one): copy the JPEGs from `images/profiles/` there after each `crop_sheets.py` run, then refresh the model. Workflow for the other sheets: paste `images/prompts/sheet_NN.txt` into ChatGPT (4 x 4 contact sheets of 16 people; sheet 10 has 7 people and 9 empty cells), save the result as `images/sheets/sheet_NN.png`, run `python images/crop_sheets.py` (160 x 160 JPEGs under 20 KB into `images/profiles/`, named from `images/sheet_map.csv`; the sheets leave almost no room above the heads, so `--top-pad`, default 0.05, adds empty backdrop above them, taking the same amount from the bottom, and `--margin`, default 0.01, trims the sides), copy them to `C:\DemoHR\profiles` and refresh the model. Keep the files small: a model text cell holds about 32,000 characters and base64 adds a third. Check the terms of the image tool before publishing the pictures; consider keeping the large sheet PNGs out of git.
- Pending renames the user must do in Desktop (F2) because visuals use them (see Measure names): `Average Tenure (years)`, `Largest Span of Control`. `Vacation Days Used per Year` is really "per employee" and could be renamed with them (a visual uses it).
- Career visuals count by the employee's current department (a version by department at the time of the event is possible).
- Page 5: `FactReviews[Level Order]` and page 6: `FactLeaveRequests[IsAbsentToday]` and `[IsInAbsenceWindow]` are calculated columns added through the MCP; press Refresh in Desktop after reopening if they show no data.
- The `Absent today` KPI card on page 6 counts only the reference date; the Gantt chart next to it also lists upcoming absences (different measures on purpose).
