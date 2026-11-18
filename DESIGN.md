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
  - Slicers on the right of the header, y 30, about 79 high: Department (x 1122, w 253), Job level (x 1394, w 231), Nationality (x 1637, w 253). Dropdown style, no background or border, label above the value, label 16 pt #5B6472, items 16 pt #1F2937, no accent bar. Synced across all pages. (Gender is not a slicer; the donut on page 1 and the Gender field in visuals cover it.)
  - KPI row: y 138, 140 high, four cards at x 329, 726, 1122, 1519, each about 372 wide. Native `cardVisual`, one value, field label hidden. The card title (20 pt Semibold, centred, #1F2937) names the KPI; the subtitle (16 pt, #5B6472, centred) gives scope or units; the value is 29 pt, centred, #4A6FA5. White background, border, padding 0. Title text and alt text are written per card.
  - Chart grid: 3 columns by 2 rows, each cell 504 x 363. Columns at x 330, 858, 1386; rows at y 300 and 687.
- **Slicers** (all pages): Department, Job level, Nationality, dropdown.
- **Card and chart style** (every chart and KPI card): white background, 1.5 px border #E5E7EB, radius 15, no shadow, no visual header.
- **Chart title** 20 pt Segoe UI Semibold #1F2937, left aligned, says what the chart shows ("Headcount by department"). **Subtitle** 16 pt Segoe UI #5B6472 on the line below, for scope or units; it may be a measure (`Text: ...`) when it depends on the data.
- **Bar charts**: horizontal, data labels at the outside end (17.25 pt, #1F2937), category labels 16 pt #1F2937, value axis hidden, no gridlines, no axis titles, neutral colour #4A6FA5 unless coloured by department. Donut: inner radius 75 %, legend off, labels show category, value and percent (14 pt).
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

Department colours are fixed and identical on every page. Do not rely on colour alone: bars carry value labels and legends carry names.

### Typography

Segoe UI, sized for the 1920 x 1080 canvas. Page title 33 pt bold; navigation title 27 pt; chart and KPI titles 20 pt Semibold; subtitles and axis labels 16 pt; data labels 17.25 pt; KPI value 29 pt; donut labels and navigation footer 14 pt (the minimum). See the layout section for where each is used.

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
| Headcount vs target | 1309, 300, 585 x 304 | Bar | `DimDepartment[Department]`, `Department Headcount`, `Headcount vs Target` (mean difference to plan); subtitle hidden |
| Team size by department | 1309, 626, 585 x 423 | Matrix | `DimDepartment[Department]` rows; Managers, Average Team Size ("Avg team"), Largest Span of Control ("Max team") values; subtitle hidden |

A chart subtitle may be hidden when the card is small (show = false); the title still says what it shows.

## Page 3: Career (built)

KPI cards: Promotions (subtitle "Including promotions with a transfer"), Department transfers (same subtitle), Position changes (change type "Position Change", "Without a promotion or transfer"), Manager changes (change type "Manager Change", "Only the manager changed"). A "Promotion + Department Transfer" counts in both Promotions and Department transfers. Source: `FactJobHistory`, never counting the Initial Assignment.

| Visual | Position (x, y, w x h) | Type | Fields |
| --- | --- | --- | --- |
| Career events per year | 330, 300, 1032 x 363 | Stacked column | `DimDate[Year]`, legend `FactJobHistory[ChangeType]`, `Career Events`; legend at the bottom |
| Months before promotion | 1386, 300, 504 x 363 | Bar | `DimDepartment[Department]` (department colours), `Average Months Before Promotion`; subtitle `Text: Months Before Promotion` (overall average) |
| Changes by type and department | 330, 687, 792 x 363 | Matrix | `ChangeType` rows, `DimDepartment[Department]` columns (current department, Acme Corporation excluded), `Career Events` |
| Latest career moves | 1146, 687, 744 x 363 | Table | Employee, Date, Change, From position, To position; newest first, Initial Assignment excluded |

Change-type colours (stacked column): Promotion #2563EB, Promotion + Department Transfer #8FAEE8, Department Transfer #4A6FA5, Position Change #E0A030, Manager Change #5B6472. Department colours are not used for change types.

Not built yet: drill-through from the matrix and table rows to page 7 (page 7 does not exist yet). Add it when page 7 is built.

## Page 4: Compensation (built)

All values are EUR per year, current salary unless stated. Pay history comes from `FactCompensation`. A promotion and a promotion with a transfer both have the reason Promotion there, so the promotion increase covers both.

KPI cards: Average salary, Median salary, Total annual payroll, Average promotion increase (share of the previous salary, about 9.0 %).

| Visual | Position (x, y, w x h) | Type | Fields |
| --- | --- | --- | --- |
| Average salary by department | 330, 300, 504 x 363 | Bar | `DimDepartment[Department]` (department colours, Acme Corporation excluded), `Average Salary`; subtitle "EUR per year, excluding the CEO" |
| Average salary by job level | 858, 300, 504 x 363 | Bar | `DimPosition[JobLevel]` (rank order), `Average Salary`; neutral colour |
| Salary by gender within level | 1386, 300, 504 x 363 | Clustered bar | `DimPosition[JobLevel]` (CEO excluded), legend `DimEmployee[Gender]`, `Average Salary`; labels in thousands with one decimal; subtitle "EUR per year, excluding the CEO (fairness check)" |
| Average salary over time | 330, 687, 792 x 363 | Line and clustered column | `DimDate[Year]` (2012 to 2026); columns `Employees at Year End` (primary axis, light tint), line `Average Salary at Year End` (secondary axis in thousands, #4A6FA5); the headcount is also in the tooltip; subtitle "Employees on payroll at year end; early years rest on few first hires" |
| Salary increases by year | 1146, 687, 744 x 363 | Clustered column | `DimDate[Year]` (2013 to 2026), `Average Annual Increase`, `Average Promotion Increase`; subtitle `Text: Promotion Increase`; navy tints (theme colour 8 lightened and darkened) instead of the bar blues |

Notes:

- Average salary over time falls from about 170k in 2012 to 69k in 2026. That is not a pay cut: the data holds only current employees, so the early years contain only the first (senior) hires, 2 people at the end of 2012 and 151 in 2026. The columns and the subtitle make this visible.
- `Average Salary at Year End` and `Employees at Year End` use the salary period valid on 31 December of the year (the reference date for 2026). Do not put the period filter in the CALCULATE filter argument: it would be evaluated under the year filter. Iterate with AVERAGEX/COUNTROWS over FILTER inside CALCULATE(..., REMOVEFILTERS(DimDate)).
- Axis labels and legends on the line/column and increases charts are 14 pt (the minimum), not 16 pt, so the year labels fit.

## Page 5: Performance (built)

Ratings are 1.0 to 5.0 from the annual reviews 2012 to 2025 (557 reviews, none for the CEO). "Latest" means the employee's latest review (`DimEmployee[LatestReviewDate]`, `LatestRating`, `LatestPerformanceLevel`).

KPI cards: Average rating (all reviews, 3.47), Exceeds or Outstanding (share of latest reviews, 47 %: 54 of 114), Without a recent review (no review in the 12 months before the reference date, 40), Reviews (number of reviews, 557).

| Visual | Position (x, y, w x h) | Type | Fields |
| --- | --- | --- | --- |
| Average rating by department | 330, 300, 504 x 363 | Bar | `DimDepartment[Department]` (department colours, Acme Corporation excluded), `Average Rating`; value axis fixed 0 to 5 |
| Average rating by manager | 858, 300, 504 x 363 | Bar, Top N filter 10 | `FactReviews[ReviewerName]`, `Average Rating` (Top 10 by the measure); neutral colour |
| Rating distribution | 1386, 300, 504 x 363 | Column | `FactReviews[Level]` (sorted by hidden `Level Order`, Needs Improvement to Outstanding), `Number of Reviews` |
| Rating by department and year | 330, 687, 792 x 363 | Matrix, heat colouring | `DimDepartment[Department]` rows, `FactReviews[ReviewYear]` columns (2018 to 2025), `Average Rating`; gradient #b7c5db to #6e8cb7 |
| Latest review per employee | 1146, 687, 744 x 363 | Table | Employee, Department, Review date, Rating, Level (all `DimEmployee`/`DimDepartment`); sorted by rating, employees without a review excluded; Level cell colour from `Level Colour` (Outstanding #CFEFE9, Exceeds #D6E4FA, Meets #E5E7EB, Needs Improvement #F8D4DD) |

Notes:

- `FactReviews[Level Order]` is a calculated column from `Rating` (thresholds 2.5, 3.5, 4.5), not from `Level`: sorting a column by a column calculated from itself is a circular dependency.
- Department and manager use the current department and the reviewer's name; reviews have no inactive relationships to `DimDepartment` or `DimManager`.

## Page 6: Leave (built)

Leave counts are working days of approved leave up to the reference date unless stated (`FactLeaveDays` has one row per approved working day, including booked future leave, which is why charts filter `IsOnOrBeforeReferenceDate`). Requests of every status are in `FactLeaveRequests` (vw_LeaveRequests, added to script 13), related to `DimEmployee` and `DimLeaveType`; it feeds Pending requests and the absent-today table.

KPI cards: Leave days (approved, 1 January to the reference date, subtitle `Text: Leave Days YTD`), Absent today (`Currently Absent`), Vacation days per employee (`Vacation Days YTD per Employee`), Pending requests (`Pending Requests`, 33).

Row 1 uses the heights of page 5 (y 300, 298 high); row 2 starts at y 618 and is 432 high.

| Visual | Position (x, y, w x h) | Type | Fields |
| --- | --- | --- | --- |
| Leave days per month by type | 330, 300, 1032 x 298 | Stacked column | `DimDate[Year-Month]`, legend `DimLeaveType[LeaveType]`, `Leave Days`; filter `IsOnOrBeforeReferenceDate` = true; Vacation #4A6FA5, Sick Leave #E0A030, Parental Leave #8FAEE8, Unpaid Leave #5B6472, Bereavement #CBD5E1 |
| Leave days by department | 1386, 300, 504 x 298 | Bar | `DimDepartment[Department]` (department colours, Acme Corporation excluded, current department), `Leave Days`; filter `IsOnOrBeforeReferenceDate` = true |
| Vacation days per employee | 330, 618, 504 x 432 | Matrix, heat colouring | `DimDepartment[Department]` rows, `DimDate[Year]` columns (2024 to 2026), `Vacation Days Used per Year`; 2026 is up to the reference date |
| Absent today | 858, 618, 1032 x 432 | Table | Employee, Department, Leave type, From, Until (`FactLeaveRequests[StartDate]`, `[EndDate]`); filter `FactLeaveRequests[IsAbsentToday]` = true; subtitle `Text: Absent Today` |

Notes:

- `FactLeaveRequests[IsAbsentToday]` is a calculated column (approved, covers the reference date). An earlier measure version was slow (about 17 s) and had to be rewritten; a column is evaluated once at refresh.
- Unpaid Leave has no days in 2026 yet (blank in the year-to-date split).

## Page 7: Employee profile (drill-through)

Drill-through target: filter on Employee. Include a back button.

| Area | Content |
| --- | --- |
| Header | Photo (placeholder until pictures exist), name, position, department, manager, hire date, tenure |
| Career timeline | Table of job-history records: date, change type, position, department, manager |
| Salary history | Stepped line chart of base salary over time, with change reasons in tooltips |
| Reviews | Column chart of rating by year |
| Leave summary | Bar of leave days by type, last 24 months |

Photos: resize to about 160 x 160 px (under 20 KB each), have Power Query read the image folder, convert each file to base64, join on `ProfileImageFileName`, and set the column's data category to Image URL. No change to the database is needed.

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
| Currently Absent | Distinct employees with an approved leave day equal to the reference date |
| Direct Reports | Count of employees whose manager is the current employee |
| Span of Control | Average Direct Reports over managers |

## Build order and checks

1. Theme JSON with the colours and fonts above.
2. Model: connect to the views in Import mode, relationships Employees (1) to every fact table on EmployeeID, a Date table marked as the date table, inactive relationships through USERELATIONSHIP.
3. Measures. Check against SQL before building visuals: Headcount 151, departments 45/25/20/35/25, one open job-history and one open compensation record per employee, at least 6 employees absent on the reference date.
4. Pages in order 1 to 7; after each page, compare its numbers with the same queries in SQL.
5. Profile photos last, once script 12 has run.

If the project format does not allow editing visuals as text, build the model, the measures and the theme, then give the user the page layout (sizes and positions above) to place the visuals in Power BI Desktop.
