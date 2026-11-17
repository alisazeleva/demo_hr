# DESIGN.md: Acme HR Dashboard (Power BI)

Design spec for the Power BI report in `powerbi/hr_dashboard`. Read this together with `PLAN.md` (Power BI plan) and `CLAUDE.md`.

- Page 1 (Workforce) is built and hand-adjusted in Power BI Desktop; it is the reference for style and layout (the early mockup https://claude.ai/artifact/WVDNJWWuenggPHhrU79dUd is superseded where they differ). Pages 2 to 7 are specified here but not mocked up yet; follow the same grid and style.
- Numbers in the early mockup (for example average tenure 5.4 years, average age 38.6, the language split) are illustrative. Real values come from the database.
- Use native Power BI visuals only (cards, bar, column, line, donut, matrix, table, decomposition tree, slicers). No custom visuals.
- Data comes from the SQL views created by script 13 (`vw_ReferenceDate`, `vw_EmployeeCurrent`, `vw_JobHistory`, `vw_CompensationHistory`, `vw_PerformanceReviews`, `vw_LeaveDays`, `vw_DepartmentHeadcountVsTarget`, `vw_OrgHierarchy`). Check the real column names in the views before building. Never use TODAY() or NOW(); take "today" from `vw_ReferenceDate` (currently 2026-11-16).

## Global layout and style

- Page size: custom 1920 x 1080 (Full HD, 16:9) on every page. (The mockup image is 1280 x 720; every size in this document is that layout x 1.5, so the page looks the same, only sharper.)
The Workforce page as built in Power BI Desktop is the reference. Copy it for every page (duplicate the page, then change titles, fields and visuals). Positions are in px on the 1920 x 1080 canvas.

- **Left navigation**, full height, x 0, y 0, 300 x 1080, navy #14213D, radius 12, no title or header.
  - "Acme HR": text box at (36, 36), 27 pt Segoe UI Semibold bold, white. "People analytics": text box at (36, 84), 16 pt, #CBD5E1.
  - Page navigator (native `pageNavigator` visual) at (24, 178), 254 x 587, vertical, cell padding 10. Text 16 pt, centred, white. Fill: default navy lightened 20 % (theme colour 8, #14213D, +20 %), hover +40 %, current page and press #2563EB. No outline, no accent bar, rounded 15, hidden pages not shown, no background or border.
  - "Data as of {reference date}": card at (0, 987), 300 x 72, 14 pt #CBD5E1, no background, border or label (measure `Text: Footer As Of`).
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
| Female / Male | #7C5CD6 / #E0A030 |

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
| Row 1, col 1 | Headcount by department | Bar | Department, `Department Headcount` | Department colours; subtitle "Employees, excluding the CEO"; the CEO reports to Acme Corporation, outside the departments |
| Row 1, col 2 | Headcount by job level | Bar | Job level (rank order, CEO first), Headcount | Neutral colour; subtitle "Employees, most senior level first" |
| Row 1, col 3 | Headcount by position | Bar | Position, Headcount | Top 5 by headcount, coloured by department; subtitle "Top 5 positions, coloured by department" |
| Row 2, col 1 | Employees by nationality | Bar | `Nationality Top 6`, Headcount | Top 6 plus "Other"; subtitle `Text: Nationality Subtitle` |
| Row 2, col 2 | Employees by native language | Bar | `Native Language Top 6`, Headcount | Top 6 plus "Other"; subtitle `Text: Language Subtitle` |
| Row 2, col 3 | Gender split | Donut | Gender, Headcount | Female #7C5CD6, Male #E0A030; subtitle `Text: Gender Subtitle` |

## Page 2: Organization

KPI cards: Managers (employees with at least one direct report), Average span of control, Largest span of control, Departments at target (x of 5).

| Visual | Type | Fields |
| --- | --- | --- |
| Reporting structure | Decomposition tree | Employee, explained by manager chain from the CEO (`vw_OrgHierarchy`) |
| Direct reports per manager | Horizontal bar, top 15 | Manager name, Direct Reports; colour by department |
| Headcount vs target | Clustered bar or bullet | Department, Target, Actual, Difference |
| Employees per manager by department | Table or matrix | Department, Managers, Average span |

## Page 3: Career

KPI cards: Promotions, Department transfers, Position changes, Manager changes (from `vw_JobHistory`, excluding Initial Assignment). A "Promotion + Department Transfer" counts in both Promotions and Department transfers.

| Visual | Type | Fields |
| --- | --- | --- |
| Career events per year | Stacked column | Year, Change type, count |
| Average months between promotions | Card plus bar by department | Months between promotions, Department |
| Changes by type and department | Matrix | Change type (rows), Department (columns) |
| Latest career moves | Table | Employee, Date, Change type, From position, To position |

Rows in the table and the matrix drill through to page 7.

## Page 4: Compensation

All values are EUR per year, current salary unless stated.

KPI cards: Average salary, Median salary, Total annual payroll, Average promotion increase (%).

| Visual | Type | Fields |
| --- | --- | --- |
| Average salary by department | Bar | Department, Average Salary |
| Average salary by job level | Bar | Job level (rank order), Average Salary |
| Average salary over time | Line | Year-end, Average salary of employees employed at that date |
| Increases by year | Clustered column | Year, Annual-increase % vs Promotion-increase % |
| Average salary by gender within level | Clustered bar | Job level, Gender, Average Salary (fairness check) |

## Page 5: Performance

KPI cards: Average rating (all reviews), Exceeds or Outstanding (% of latest reviews), Employees without a recent review, Number of reviews.

| Visual | Type | Fields |
| --- | --- | --- |
| Average rating by department | Bar | Department, Average Rating |
| Average rating by manager | Bar, top 10 managers | Reviewer name, Average Rating |
| Rating distribution | Column | Performance level (4 levels in order), count |
| Rating by department and year | Matrix with heat colouring | Department (rows), Review year (columns), Average Rating |
| Latest review per employee | Table | Employee, Department, Review date, Rating, Level; conditional colour on Level |

## Page 6: Leave

All leave counts are working days of Approved leave, up to the reference date unless stated.

KPI cards: Leave days (year to date), Employees absent today, Average vacation days per employee (year to date), Pending requests.

| Visual | Type | Fields |
| --- | --- | --- |
| Leave days per month by type | Stacked column | Month, Leave type, Leave Days |
| Leave days by department | Bar | Department, Leave Days |
| Vacation usage by department | Matrix | Department, Vacation days per employee |
| Absent today | Table | Employee, Department, Leave type, Until date |

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
| Total Payroll | Sum of current annual salaries |
| Average Tenure (years) | Average of (reference date minus hire date) in years |
| Promotions | Job-history rows whose change type contains "Promotion" |
| Department Transfers | Job-history rows whose change type contains "Department Transfer" |
| Average Months Between Promotions | Average gap between consecutive promotions of the same employee |
| Average Rating | Average of OverallRating |
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
