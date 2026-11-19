# DESIGN.md: Acme HR Dashboard (Power BI)

Design spec for the Power BI report in `powerbi/hr_dashboard`. Read this together with `PLAN.md` (Power BI plan) and `CLAUDE.md`.

- Page 1 (Workforce) is built and hand-adjusted in Power BI Desktop; it is the reference for style and layout (the early mockup https://claude.ai/artifact/WVDNJWWuenggPHhrU79dUd is superseded where they differ). Pages 2 to 7 are specified here but not mocked up yet; follow the same grid and style.
- Numbers in the early mockup (for example average tenure 5.4 years, average age 38.6, the language split) are illustrative. Real values come from the database.
- Use native Power BI visuals only (cards, bar, column, line, donut, matrix, table, decomposition tree, slicers). No custom visuals.
- Data comes from the SQL views created by script 13, modelled as a star schema. Model tables: `DimEmployee` (vw_DimEmployee), `DimDepartment`, `DimPosition`, `DimManager`, `DimLeaveType`, `DimDate`, and facts `FactJobHistory`, `FactCompensation`, `FactReviews`, `FactLeaveDays`, `FactWorkforcePlan`; `ReferenceDate` (vw_ReferenceDate) holds "today" (currently 2026-11-16) and `_Measures` holds the measures. Attributes live in one dimension only: use `DimDepartment[Department]`, `DimPosition[JobLevel]`, `DimPosition[PositionTitle]` and `DimManager[ManagerName]`. Facts relate to `DimEmployee` and `DimDate` (active) and to `DimDepartment`, `DimPosition` and `DimManager` through inactive relationships (use USERELATIONSHIP for the department, position or manager at the time of the event). Check the real column names in the views before building. Never use TODAY() or NOW().

## Global layout and style

- Page size: custom 1920 x 1080 (Full HD, 16:9) on every page. (The mockup image is 1280 x 720; every size in this document is that layout x 1.5, so the page looks the same, only sharper.)
The Workforce page as built in Power BI Desktop is the reference. Copy it for every page (duplicate the page, then change titles, fields and visuals). Positions are in px on the 1920 x 1080 canvas.

- **Left navigation**, full height, x 0, y 0, 300 x 1080, navy #14213D, radius 12, no title or header.
  - "Acme HR": text box at (36, 36), 27 pt Segoe UI Semibold bold, white. "People analytics": text box at (36, 84), 16 pt, #CBD5E1.
  - Page navigator (native `pageNavigator` visual) at (24, 178), 254 x 587, vertical, cell padding 10. Text 16 pt, centred, white. Fill: default navy lightened 20 % (theme colour 8, #14213D, +20 %), hover +40 %, current page and press #2563EB. No outline, no accent bar, rounded 15, hidden pages not shown, no background or border.
  - "Data as of {reference date}": card at (0, 978), 300 x 72, 14 pt #CBD5E1, no background, border or label (measure `Text: Footer As Of`). Next to it an "information" action button icon at (100, 1029), 100 x 40, no fill, icon #CBD5E1 (reserved for a data-source note; no action yet).
- **Main area**: starts at x 330 and ends at x 1890 (30 px right padding); 24 px gaps.
  - Header: page title text box at (330, 19), 33 pt Semibold bold, #1F2937. Under it, a subtitle card at (317, 74), 16 pt #5B6472, no background or border, showing "Acme Corporation · {n} current employees · as of {reference date}" (measure `Text: Header Subtitle`).
  - Slicers on the right of the header, y 30, about 79 high: Department (x 1122, w 253), Job level (x 1394, w 231) and a page-specific third slicer (x 1637 on pages 1 and 2, x 1640 on pages 3 to 6, w 253): Nationality (pages 1 and 4), Manager (pages 2 and 5), Change type (page 3), Leave type (page 6). Dropdown style, no background or border, label above the value, label 16 pt #5B6472, items 16 pt #1F2937, no accent bar. Department and Job level are synced across pages 1 to 6, and the Nationality slicers of pages 1 and 4 are synced; the Manager slicers of pages 2 and 5 (sync group "Manager") are not synced with each other. (Gender is not a slicer; the donut on page 1 and the Gender field in visuals cover it.) The Employee profile page has no header slicers, only an employee dropdown (see page 7).
  - KPI row: y 138, 140 high, four cards at x 329, 726, 1122, 1519, each about 372 wide. Native `cardVisual`, one value, field label hidden. The card title (20 pt Semibold, centred, #1F2937) names the KPI; the subtitle (16 pt, #5B6472, centred) gives scope or units; the value is 29 pt, centred, #4A6FA5. White background, border, padding 0. Title text and alt text are written per card.
  - Chart grid: 3 columns by 2 rows, each cell 504 x 363. Columns at x 330, 858, 1386; rows at y 300 and 687. Pages 1, 2 and 4 follow it. Pages 3, 5, 6 and 7 use hand-adjusted layouts (different row heights or column widths) that are recorded in their sections below; follow those, not the grid, when editing them.
- **Slicers** (pages 1 to 6): Department, Job level and one page-specific slicer, dropdown (see the header bullet above).
- **Card and chart style** (every chart and KPI card): white background, 1.5 px border #E5E7EB, radius 15, no shadow, no visual header.
- **Chart title** 20 pt Segoe UI Semibold #1F2937, left aligned, says what the chart shows ("Headcount by department"). **Subtitle** 16 pt Segoe UI #5B6472 on the line below, for scope or units; it may be a measure (`Text: ...`) when it depends on the data.
- **Bar charts**: horizontal, data labels at the outside end (14 pt, #1F2937), category labels 14 pt #1F2937 (16 pt on the bars of pages 5 to 7 listed below), value axis hidden, no gridlines, no axis titles, neutral colour #4A6FA5 unless coloured by department. Donut: inner radius 75 %, legend off, labels show category, value and percent (14 pt).
- **Other charts** (column, line, combo, clustered): axis labels and legends 14 pt, light gridlines #E5E7EB, value labels only where they fit.
- **Tables and matrices**: values 14 pt, column headers 16 pt, totals 16 pt, matrix row headers 14 pt; same card style (border, radius 15, title and subtitle) as the charts. Heat colouring on matrices uses a gradient from #b7c5db to #6e8cb7.
- **Department bars on pages 4, 5 and 6** (average salary, average rating, leave days by department) use one colour, theme colour 8 (#14213D), not the department colours; the department colours remain on pages 1 and 3.
- Units always labelled (EUR, years, days, %).
- **Every visual**: alt text, tab order left to right then top to bottom, `Segoe UI` fonts, no emoji.

### Colours (put these in a theme JSON in `powerbi/`)

| Use | Colour |
| --- | --- |
| Page background | #F3F4F6 |
| Card background / border | #FFFFFF / #E5E7EB |
| Text / muted text | #1F2937 / #5B6472 |
| Navigation background / text | #14213D / #CBD5E1 |
| Active page / accent | #2563EB |
| Neutral bars | #4A6FA5 |
| Technology | #2563EB |
| Finance | #0E9F8E |
| Human Resources | #D9822B |
| Sales | #7C5CD6 |
| Customer Experience | #C8446A |
| Female / Male | #E0A030 / #5B6472 (changed by hand in Desktop; used on the page 1 donut and the page 4 gender chart) |

Where department colours are used (pages 1 and 3) they are fixed and identical. Do not rely on colour alone: bars carry value labels and legends carry names.

### Typography

Segoe UI, sized for the 1920 x 1080 canvas. Page title 33 pt bold; navigation title 27 pt; chart and KPI titles 20 pt Semibold; subtitles and table or matrix column headers 16 pt; chart data labels, axis labels, legends, table and matrix values and the navigation footer 14 pt (the minimum); KPI value 29 pt. Profile header cards on page 7 use 16 pt values and a 29 pt name. See the layout section for where each is used. The theme file (`powerbi/acme_hr_theme.json`, identical to the copy in the report's `StaticResources/RegisteredResources/`) stores 20.25 pt for titles and 17.25 pt for subtitles and labels, the values Desktop writes for the nominal 20 and 16 pt.

### Accessibility

Alt text on every visual, sensible tab order, text contrast of at least 4.5:1, no emoji.

## Page 1: Workforce (built; this is the reference)

Header subtitle, KPI cards and subtitles as built:

| KPI card | Title | Subtitle |
| --- | --- | --- |
| Headcount | Total employees | `Text: Headcount Split` (1 CEO + 150 in departments) |
| Average Tenure (years) | Average tenure | Since hire date |
| Average Age | Average age | `Text: Age Range` |
| Departments | Departments | One company, no subdepartments |

| Cell | Visual | Type | Fields | Notes |
| --- | --- | --- | --- | --- |
| Row 1, col 1 | Headcount by job level | Bar | `DimPosition[JobLevel]` (rank order, CEO first), Headcount | Neutral colour; subtitle "Employees, most senior level first" |
| Row 1, col 2 | Headcount by department | Bar | `DimDepartment[Department]`, `Department Headcount` | Department colours; subtitle "Employees, excluding the CEO"; the CEO reports to Acme Corporation, outside the departments |
| Row 1, col 3 | Headcount by position | Bar | `DimPosition[PositionTitle]`, Headcount, legend `DimDepartment[Department]` | Top N positions by headcount (Top N filter), bars coloured by department through the legend; subtitle "Positions, coloured by department" |
| Row 2, col 1 | Employees by nationality | Bar | `Nationality Top 6`, Headcount | Top 6 plus "Other"; subtitle `Text: Nationality Subtitle` |
| Row 2, col 2 | Employees by native language | Bar | `Native Language Top 6`, Headcount | Top 6 plus "Other"; subtitle `Text: Language Subtitle` |
| Row 2, col 3 | Gender split | Donut | Gender, Headcount | Female #E0A030, Male #5B6472; subtitle `Text: Gender Subtitle` |

## Page 2: Organization (built)

KPI cards: Managers (employees with at least one direct report), Average team size (direct reports per manager), Largest team (largest number of direct reports; subtitle from `Text: Teams with Largest Span`), Departments at target (x of 5; subtitle `Text: Departments at Target`).

The chart area is not the 3 x 2 grid: a tall decomposition tree on the left and two stacked cards on the right.

| Visual | Position (x, y, w x h) | Type | Fields |
| --- | --- | --- | --- |
| Reporting structure | 330, 300, 952 x 749 | Decomposition tree | Analyze `Headcount`; explain by `DimDepartment[Department]`, `DimManager[ManagerName]`, `DimPosition[JobLevel]`, `DimEmployee[FullName]`; Acme Corporation excluded |
| Headcount vs target | 1309, 300, 585 x 352 | Bar | `DimDepartment[Department]`, `Department Headcount` (#4A6FA5), `Headcount vs Target` (grey tint, theme colour 7 at +60 %), legend 16 pt at the bottom; subtitle hidden |
| Team size by department | 1309, 675, 585 x 375 | Matrix | `DimDepartment[Department]` rows; Managers, Average Team Size ("Avg team"), Largest Span of Control ("Max team") values; subtitle hidden |

A chart subtitle may be hidden when the card is small (show = false); the title still says what it shows.

## Page 3: Career (built; layout hand-adjusted)

KPI cards: Promotions (subtitle "Including promotions with a transfer"), Department transfers (same subtitle), Position changes (change type "Position Change", "Without a promotion or transfer"), Manager changes (change type "Manager Change", "Only the manager changed"). A "Promotion + Department Transfer" counts in both Promotions and Department transfers. Source: `FactJobHistory`, never counting the Initial Assignment. The third slicer (x 1640) is Change type.

| Visual | Position (x, y, w x h) | Type | Fields |
| --- | --- | --- | --- |
| Career events per year | 330, 300, 1046 x 380 | Matrix, heat colouring | rows `FactJobHistory[ChangeType]`, columns `DimDate[Year]`, `Career Events`; subtitle "Changes after hire by type; the Initial Assignment at hire is not counted" |
| Career events by department | 1401, 300, 492 x 380 | Bar | `DimDepartment[Department]` (department colours, current department), `Career Events`; subtitle "Number of career events, current department" |
| Latest career moves | 330, 713, 1046 x 337 | Table | Date, Employee, Change, From position, To position; newest first, Initial Assignment excluded |
| Months before promotion | 1401, 713, 489 x 336 | Bar | `DimDepartment[Department]` (department colours), `Average Months Before Promotion`; subtitle `Text: Months Before Promotion` (overall average) |

The earlier stacked column by year and the change-type colours were replaced by the matrix; change-type colours are no longer used. Drill-through to the Employee profile page works from any visual that contains the employee name (this table, page 5's and page 6's tables): right-click a row, then Drill through.

## Page 4: Compensation (built)

All values are EUR per year, current salary unless stated. Pay history comes from `FactCompensation`. A promotion and a promotion with a transfer both have the reason Promotion there, so the promotion increase covers both. The third slicer (x 1640) is Nationality.

KPI cards: Average salary, Median salary, Total annual payroll, Average promotion increase (share of the previous salary, about 9.0 %).

| Visual | Position (x, y, w x h) | Type | Fields |
| --- | --- | --- | --- |
| Average salary by department | 330, 300, 504 x 363 | Bar | `DimDepartment[Department]` (one navy colour, theme colour 8; Acme Corporation excluded), `Average Salary`; subtitle "EUR per year, excluding the CEO" |
| Average salary by job level | 858, 300, 504 x 363 | Bar | `DimPosition[JobLevel]` (rank order), `Average Salary`; neutral colour |
| Salary by gender within level | 1386, 300, 504 x 363 | Clustered bar | `DimPosition[JobLevel]` (CEO excluded), legend `DimEmployee[Gender]` (Female #E0A030, Male #5B6472), `Average Salary`; labels in thousands with one decimal; subtitle "EUR per year, excluding the CEO (fairness check)" |
| Average salary over time | 330, 687, 792 x 363 | Line and clustered column | `DimDate[Year]` (2012 to 2026); columns `Employees at Year End` (primary axis, theme colour 5 at +60 %), line `Average Salary at Year End` (secondary axis in thousands, #4A6FA5); the headcount is also in the tooltip; subtitle "Employees on payroll at year end; early years rest on few first hires" |
| Salary increases by year | 1146, 687, 744 x 363 | Clustered column | `DimDate[Year]` (2013 to 2026), `Average Annual Increase` (theme colour 8 at +40 %), `Average Promotion Increase` (theme colour 8 at -25 %); subtitle `Text: Promotion Increase` |

Notes:

- Average salary over time falls from about 170k in 2012 to 69k in 2026. That is not a pay cut: the data holds only current employees, so the early years contain only the first (senior) hires, 2 people at the end of 2012 and 151 in 2026. The columns and the subtitle make this visible.
- `Average Salary at Year End` and `Employees at Year End` use the salary period valid on 31 December of the year (the reference date for 2026). Do not put the period filter in the CALCULATE filter argument: it would be evaluated under the year filter. Iterate with AVERAGEX/COUNTROWS over FILTER inside CALCULATE(..., REMOVEFILTERS(DimDate)).

## Page 5: Performance (built; layout hand-adjusted)

Ratings are 1.0 to 5.0 from the annual reviews 2012 to 2025 (557 reviews, none for the CEO). "Latest" means the employee's latest review (`DimEmployee[LatestReviewDate]`, `LatestRating`, `LatestPerformanceLevel`). The third slicer (x 1640) is Manager.

KPI cards: Average rating (all reviews, 3.47), Exceeds or Outstanding (share of latest reviews, 47 %: 54 of 114), Without a recent review (no review in the 12 months before the reference date, 40), Reviews (number of reviews, 557).

Row 1 is 346 high (y 300), row 2 starts at y 668 and is 382 high.

| Visual | Position (x, y, w x h) | Type | Fields |
| --- | --- | --- | --- |
| Average rating by department | 330, 300, 505 x 346 | Bar | `DimDepartment[Department]` (one navy colour, Acme Corporation excluded), `Average Rating`; category labels 16 pt |
| Average rating by manager | 858, 300, 505 x 346 | Bar, Top N filter 5 | `FactReviews[ReviewerName]`, `Average Rating` (Top 5 by the measure); neutral colour; category labels 16 pt; subtitle "Top 5 managers by the average rating they gave" |
| Rating distribution | 1386, 300, 505 x 346 | Bar | `FactReviews[Level Long]` ("Meets Expectations (ME)", sorted by hidden `Level Order`), `Number of Reviews`; clicking a bar cross-filters the table below |
| Rating by department and year | 330, 668, 792 x 382 | Matrix, heat colouring | `DimDepartment[Department]` rows, `FactReviews[ReviewYear]` columns (2018 to 2025), `Average Rating`; gradient #b7c5db to #6e8cb7 |
| Latest review per employee | 1146, 668, 744 x 382 | Table | Employee, Department, Review date, Rating, Level (`DimEmployee[Latest Level Short]`: NI, ME, EE, O); sorted by rating, employees without a review excluded; Level cell colour from `Level Colour` (Outstanding #CFEFE9, Exceeds #D6E4FA, Meets #E5E7EB, Needs Improvement #F8D4DD); visual filter `Latest Level in Selection` = 1 |

Notes:

- `FactReviews[Level Order]` is a calculated column from `Rating` (thresholds 2.5, 3.5, 4.5), not from `Level`: sorting a column by a column calculated from itself is a circular dependency. `Level Long` and `Level` are sorted by it.
- `Latest Level in Selection` keeps both `Level` and `Level Long` so the cross-filter works whichever of them the chart uses.
- Department and manager use the current department and the reviewer's name; reviews have no inactive relationships to `DimDepartment` or `DimManager`.

## Page 6: Leave (built; layout hand-adjusted)

Leave counts are working days of approved leave up to the reference date unless stated (`FactLeaveDays` has one row per approved working day, including booked future leave, which is why charts filter `IsOnOrBeforeReferenceDate` or by date). Requests of every status are in `FactLeaveRequests` (vw_LeaveRequests, added to script 13), related to `DimEmployee` and `DimLeaveType`; it feeds Pending requests and the absent-today table. The third slicer (x 1640) is Leave type.

KPI cards: Leave days (approved, 1 January to the reference date, subtitle `Text: Leave Days YTD`), Absent today (`Currently Absent`), Vacation days per employee (`Vacation Days YTD per Employee`), Pending requests (`Pending Requests`, 33).

| Visual | Position (x, y, w x h) | Type | Fields |
| --- | --- | --- | --- |
| Vacation days per employee | 330, 305, 597 x 398 | Matrix, heat colouring | `DimDepartment[Department]` rows, `DimDate[Year]` columns (2024 to 2026), `Vacation Days Used per Year`; 2026 is up to the reference date |
| Leave days per month by type | 953, 305, 937 x 398 | Stacked column | axis `DimDate[Year]` and `DimDate[Month]` (hierarchy), legend `DimLeaveType[LeaveType]`, `Leave Days`; a relative-date filter on `DimDate[Date]` is set; Vacation #4A6FA5, Sick Leave #E0A030, Parental Leave #8FAEE8, Unpaid Leave #5B6472, Bereavement #CBD5E1 |
| Leave days by department | 329, 730, 602 x 320 | Bar | `DimDepartment[Department]` (one navy colour, Acme Corporation excluded, current department), `Leave Days`; filter `IsOnOrBeforeReferenceDate` = true; category labels 16 pt |
| Absent today | 953, 730, 937 x 320 | Table | Employee, Department, Leave type, From, Until (`FactLeaveRequests[StartDate]`, `[EndDate]`); filter `FactLeaveRequests[IsAbsentToday]` = true; subtitle `Text: Absent Today` |

Notes:

- `FactLeaveRequests[IsAbsentToday]` is a calculated column (approved, covers the reference date). An earlier measure version was slow (about 17 s) and had to be rewritten; a column is evaluated once at refresh.
- Unpaid Leave has no days in 2026 yet (blank in the year-to-date split).
- Vacation days per employee divides approved vacation days by employees hired by the end of the year (the card divides by the current headcount); employees hired part-way through the year count in full.

## Page 7: Employee profile (built; hidden drill-through page; layout hand-adjusted)

The page is hidden in view mode and filtered on `DimEmployee[FullName]` (unique across the 151 employees) through a drill-through binding. From any visual that contains the employee name (the page 3 latest career moves table, the page 5 latest review table, the page 6 absent-today table) right-click a row, then Drill through, then Employee profile. An employee dropdown slicer (1558, 42, 325 x 79) lets you pick a person without drilling. A Back button (action Back, 1846, 0, 74 x 73) is at the top right; the page title is followed by a text box "Drill-through page" (330, 85, 16 pt, #5B6472) instead of the subtitle card.

Profile fields that live in `DimPosition`, `DimDepartment` and `DimManager` are read with LOOKUPVALUE on the keys in `DimEmployee` (those dimensions filter `DimEmployee`, not the other way round), so SELECTEDVALUE on them would return nothing.

Header band: a rounded rectangle (330, 141, 1560 x 150, border only) holding borderless cards with the field name as label, 16 pt left-aligned values (the name is 29 pt) and a subtitle measure under the value.

| Area | Position (x, y, w x h) | Content |
| --- | --- | --- |
| Picture placeholder | 351, 152, 120 x 120 | Oval shape (theme colour 8 at +60 %) with the initials (`Text: Profile Initials`, 32 pt bold) until pictures exist (script 12 was skipped) |
| Name | 479, 146, 477 x 81 | `Text: Profile Name`, subtitle `Text: Profile Job Level`; below it `Text: Profile Number` (488, 212) |
| Position | 956, 151, 348 x 61 | `Text: Profile Role` (position) |
| Department | 1304, 151, 283 x 61 | `Text: Profile Department` |
| Manager | 1587, 150, 294 x 61 | `Text: Profile Manager` (CEO: "Reports to the board"), subtitle "Direct manager" |
| Tenure | 960, 216, 343 x 61 | `Text: Profile Tenure`, subtitle `Text: Profile Hire Date` |
| Current salary | 1303, 216, 283 x 61 | `Text: Profile Salary`, subtitle `Text: Profile Salary Note` |
| Latest review | 1587, 216, 294 x 61 | `Text: Profile Rating`, subtitle `Text: Profile Rating Note` |
| Career timeline | 330, 317, 792 x 372 | Table of `FactJobHistory`: Date, Change, Position, Department, Manager, oldest first |
| Salary history | 1146, 317, 744 x 372 | Stepped line of `Base Salary` over `FactCompensation[EffectiveDate]`; tooltip with `Reason` and `Salary Change` |
| Leave summary | 330, 717, 325 x 332 | Bar of `Leave Days Last 24 Months` by `DimLeaveType[LeaveType]`, category labels 16 pt |
| Performance reviews | 680, 717, 366 x 332 | Column chart of `Average Rating` by `FactReviews[ReviewYear]`; bars coloured by a 3-colour gradient on the rating (#C8446A low, #92a9c9 mid, #4A6FA5 high) |
| Review history | 1071, 717, 819 x 332 | Table of `FactReviews`: Review date, Level, Comments; the Level cell is coloured by `Review Level Colour` (same palette as `Level Colour`) |

Photos: resize to about 160 x 160 px (under 20 KB each), have Power Query read the image folder, convert each file to base64, join on `ProfileImageFileName`, and set the column's data category to Image URL. No change to the database is needed. When pictures exist, replace the initials in the oval with an image visual.

## Measures (build in the `_Measures` table; each with a description)

| Measure | Definition |
| --- | --- |
| Headcount | Count of current employees (respecting slicers) |
| Headcount vs Target | Headcount minus department target |
| Average Salary / Median Salary | Over current salaries |
| Average Salary at Year End / Employees at Year End | Average salary and headcount on 31 December of the selected year (reference date for 2026), from the salary period valid on that date |
| Average Annual Increase / Average Promotion Increase | Average ChangePct of the pay-history rows with reason Annual Increase / Promotion, as a share |
| Total Payroll | Sum of current annual salaries |
| Average Tenure (years) | Average of (reference date minus hire date) in years |
| Promotions | Job-history rows whose change type contains "Promotion" |
| Department Transfers | Job-history rows whose change type contains "Department Transfer" |
| Average Months Before Promotion | Average months in the job before a promotion: from the previous promotion, or from hire for a first promotion, to each promotion date (every promoted employee contributes) |
| Average Rating | Average of OverallRating |
| Number of Reviews / Exceeds or Outstanding Share | Review count; share of employees with a latest review whose latest level is Exceeds Expectations or Outstanding |
| Employees Without Recent Review | Employees with no review dated within 12 months before the reference date |
| Leave Days | Count of rows in `vw_LeaveDays` (one row per working day) |
| Vacation Days per Employee | Vacation Leave Days divided by Headcount |
| Leave Days YTD / Vacation Days YTD per Employee | Approved leave days (vacation days divided by Headcount) from 1 January of the reference year to the reference date, regardless of date filters |
| Pending Requests | Leave requests with status Pending (`FactLeaveRequests`) |
| Leave Days Last 24 Months | Approved leave days in the 24 months up to the reference date |
| Level Colour / Review Level Colour | Hex colour of the latest level of the employee (page 5 table) / of the level of each review row (page 7 table), for conditional formatting |
| Latest Level in Selection | 1 when the employee's latest level is among the levels selected in the rating distribution chart (visual filter of the page 5 table) |
| Base Salary / Salary Change | Salary of a pay-history record and its change against the previous salary, for the profile salary history |
| Text: Profile ... | Name, number, role, department, job level, manager, tenure, hire date, salary, salary note, rating, rating note and initials of the selected employee (page 7 header) |
| Currently Absent | Distinct employees with an approved leave day equal to the reference date |
| Direct Reports | Count of employees whose manager is the current employee |
| Span of Control | Average Direct Reports over managers |

Calculated columns added for the report: `DimEmployee[Latest Level Short]` (NI, ME, EE, O), `FactReviews[Level Long]` (for example "Meets Expectations (ME)"), hidden `FactReviews[Level Order]` (sort key from the rating thresholds), `FactLeaveRequests[IsAbsentToday]`.

## Build order and checks

1. Theme JSON with the colours and fonts above.
2. Model: connect to the views in Import mode, relationships Employees (1) to every fact table on EmployeeID, a Date table marked as the date table, inactive relationships through USERELATIONSHIP.
3. Measures. Check against SQL before building visuals: Headcount 151, departments 45/25/20/35/25, one open job-history and one open compensation record per employee, at least 6 employees absent on the reference date.
4. Pages in order 1 to 7; after each page, compare its numbers with the same queries in SQL.
5. Profile photos last, once script 12 has run.

If the project format does not allow editing visuals as text, build the model, the measures and the theme, then give the user the page layout (sizes and positions above) to place the visuals in Power BI Desktop.
