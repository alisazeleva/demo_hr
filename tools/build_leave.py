"""Generator of page 6 (Leave): copies the shell, KPI card, bar, matrix and table styles from the hand-adjusted page 5, then adds the visuals.
Overwrites the page 6 visuals only. Run tools/validate_pbir.py afterwards."""
import json, glob, copy, hashlib, os, shutil
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
base = os.path.join(REPO, 'hr_dashboard.Report', 'definition', 'pages')
pages = {}
for f in glob.glob(os.path.join(base, '*', 'page.json')):
    pages[json.load(open(f, encoding='utf-8'))['displayName']] = os.path.dirname(f)
P5, P6 = pages['Performance'], pages['Leave']
L = lambda v: {"expr": {"Literal": {"Value": v}}}
SOL = lambda h: {"solid": {"color": L("'%s'" % h)}}
def nid(l): return hashlib.md5(('hr_dashboard|leave|' + l).encode()).hexdigest()[:20]
def load(p): return [json.load(open(f, encoding='utf-8')) for f in glob.glob(os.path.join(p, 'visuals', '*', 'visual.json'))]
src5 = load(P5)
SCHEMA = src5[0]['$schema']
def find(src, t, x=None, y=None):
    for d in src:
        p = d['position']
        if d['visual']['visualType'] == t and (x is None or abs(p['x'] - x) < 3) and (y is None or abs(p['y'] - y) < 3):
            return copy.deepcopy(d)
    raise Exception((t, x, y))
out = {}
def add(label, d):
    d['name'] = nid(label); out[label] = d; return d
def alt(d, t):
    vc = d['visual'].setdefault('visualContainerObjects', {})
    vc['general'] = [{"properties": {"altText": L("'%s'" % t.replace("'", "''"))}}]
def meas(p): return {"Measure": {"Expression": {"SourceRef": {"Entity": "_Measures"}}, "Property": p}}
def col(t, p): return {"Column": {"Expression": {"SourceRef": {"Entity": t}}, "Property": p}}
def cproj(t, p, active=True, **kw):
    d = {"field": col(t, p), "queryRef": "%s.%s" % (t, p), "nativeQueryRef": p}
    if active: d["active"] = True
    d.update(kw); return d
def mproj(p, **kw):
    d = {"field": meas(p), "queryRef": "_Measures." + p, "nativeQueryRef": p}; d.update(kw); return d
def titles(d, t, s, at, show_sub=True):
    vc = d['visual']['visualContainerObjects']
    vc['title'][0]['properties']['text'] = L("'%s'" % t)
    sp = vc['subTitle'][0]['properties']
    sp['text'] = s if isinstance(s, dict) else L("'%s'" % s)
    sp['show'] = L('true' if show_sub else 'false')
    alt(d, at)
def not_in(label, entity, prop, value):
    return {"name": nid(label), "field": col(entity, prop), "type": "Categorical",
            "filter": {"Version": 2, "From": [{"Name": "e", "Entity": entity, "Type": 0}],
                       "Where": [{"Condition": {"Not": {"Expression": {"In": {"Expressions": [{"Column": {"Expression": {"SourceRef": {"Source": "e"}}, "Property": prop}}],
                                  "Values": [[{"Literal": {"Value": "'%s'" % value}}]]}}}}}]},
            "objects": {"general": [{"properties": {"isInvertedSelectionMode": L("true")}}]}}

# ---- shell copied from page 3 (navigation, header, slicers, footer, info button)
for t, x, y, k in [('textbox', 0, 0, 'navbg'), ('textbox', 36, 36, 'navtitle'), ('textbox', 36, 84, 'navsub'),
                   ('pageNavigator', None, None, 'nav'), ('card', 0, None, 'footer'), ('actionButton', None, None, 'info'),
                   ('cardVisual', 317, 74, 'subtitle'), ('textbox', 330, 19, 'title')]:
    d = add(k, find(src5, t, x, y))
    if k == 'title':
        d['visual']['objects']['general'][0]['properties']['paragraphs'][0]['textRuns'][0]['value'] = 'Leave'
        alt(d, 'Page title: Leave')
for x, k in [(1122, 'Department'), (1394, 'JobLevel'), (1637, 'Nationality')]:
    add('slicer' + k, find(src5, 'slicer', x, 30))

# ---- KPI cards (template: page 5 card)
tpl = find(src5, 'cardVisual', 329, 138)
def kpi(x, m, title, sub, alttext):
    d = copy.deepcopy(tpl); q = d['visual']['query']
    q['queryState']['Data']['projections'] = [mproj(m)]
    q['sortDefinition']['sort'][0]['field'] = meas(m)
    vc = d['visual']['visualContainerObjects']
    vc['title'][0]['properties']['text'] = L("'%s'" % title)
    vc['subTitle'][0]['properties']['text'] = sub if isinstance(sub, dict) else L("'%s'" % sub)
    alt(d, alttext); d['position'].update(x=x, y=137.5, width=373.9, height=139.7)
    add('kpi' + m, d)
kpi(328.7, 'Leave Days YTD', 'Leave days', {"expr": meas('Text: Leave Days YTD')}, 'Approved leave working days this year to date')
kpi(726.2, 'Currently Absent', 'Absent today', 'Employees on approved leave', 'Number of employees on approved leave on the reference date')
kpi(1121.6, 'Vacation Days YTD per Employee', 'Vacation days per employee', 'Working days, year to date', 'Average vacation working days per employee this year to date')
kpi(1519.0, 'Pending Requests', 'Pending requests', 'Booked leave awaiting approval', 'Number of pending leave requests')

W1, H1, Y1 = 504.4, 298.0, 300.0        # row 1 as hand-adjusted on page 5
Y2, H2 = 618.0, 432.0                   # row 2
deptbar = find(src5, 'barChart', 330, 300)
VC = deptbar['visual']['visualContainerObjects']
AX = lambda **k: {"properties": dict({"labelColor": SOL('#1F2937'), "fontSize": L("14D"), "fontFamily": L("'Segoe UI'"), "showAxisTitle": L("false")}, **k)}
def bool_filter(label, entity, prop, value):
    return {"name": nid(label), "field": col(entity, prop), "type": "Categorical",
            "filter": {"Version": 2, "From": [{"Name": "e", "Entity": entity, "Type": 0}],
                       "Where": [{"Condition": {"In": {"Expressions": [{"Column": {"Expression": {"SourceRef": {"Source": "e"}}, "Property": prop}}],
                                                       "Values": [[{"Literal": {"Value": value}}]]}}}]}}
TODATE = lambda l: bool_filter(l, 'FactLeaveDays', 'IsOnOrBeforeReferenceDate', 'true')

# 1 leave days per month by type (stacked column, up to the reference date)
LT = ['Vacation', 'Sick Leave', 'Parental Leave', 'Unpaid Leave', 'Bereavement']
LC = ['#4A6FA5', '#E0A030', '#8FAEE8', '#5B6472', '#CBD5E1']
sc = {"$schema": SCHEMA, "name": '', "position": {"x": 330, "y": Y1, "z": 1, "height": H1, "width": 1032, "tabOrder": 1},
      "visual": {"visualType": "columnChart",
                 "query": {"queryState": {"Category": {"projections": [cproj('DimDate', 'Year-Month')]},
                                           "Series": {"projections": [cproj('DimLeaveType', 'LeaveType')]},
                                           "Y": {"projections": [mproj('Leave Days')]}}},
                 "objects": {"dataPoint": [{"properties": {"fill": SOL(c)},
                                            "selector": {"data": [{"scopeId": {"Comparison": {"ComparisonKind": 0,
                                                "Left": col('DimLeaveType', 'LeaveType'), "Right": {"Literal": {"Value": "'%s'" % n}}}}}]}}
                                           for n, c in zip(LT, LC)],
                             "labels": [{"properties": {"show": L("false")}}],
                             "legend": [{"properties": {"show": L("true"), "position": L("'Bottom'"), "fontSize": L("14D"),
                                                         "labelColor": SOL('#1F2937'), "fontFamily": L("'Segoe UI'")}}],
                             "categoryAxis": [AX(axisType=L("'Categorical'"))],
                             "valueAxis": [{"properties": {"labelColor": SOL('#5B6472'), "fontSize": L("14D"), "fontFamily": L("'Segoe UI'"),
                                                            "showAxisTitle": L("false"), "gridlineShow": L("true"), "gridlineColor": SOL('#E5E7EB')}}],
                             "general": [{"properties": {"responsive": L("false")}}]},
                 "visualContainerObjects": copy.deepcopy(VC), "drillFilterOtherVisuals": True},
      "filterConfig": {"filters": [TODATE('f_month_todate')]}}
titles(sc, 'Leave days per month by type', 'Approved working days from January 2024 up to the reference date',
       'Stacked column chart: approved leave working days per month by leave type.')
add('months', sc)

# 2 leave days by department (department colours)
d = copy.deepcopy(deptbar); q = d['visual']['query']
q['queryState']['Y']['projections'] = [mproj('Leave Days')]
q['sortDefinition']['sort'][0]['field'] = meas('Leave Days')
d['filterConfig'] = {"filters": [not_in('f_dept', 'DimDepartment', 'Department', 'Acme Corporation'), TODATE('f_dept_todate')]}
va = d['visual']['objects']['valueAxis'][0]['properties']; va.pop('start', None); va.pop('end', None)
titles(d, 'Leave days by department', 'Approved working days to date; current department', 'Bar chart: approved leave working days per department.')
d['position'].update(x=1386, y=Y1, width=W1, height=H1)
add('dept', d)

# 3 vacation days per employee by department and year (matrix, heat colouring; template: page 5 matrix)
mx = find(src5, 'pivotTable')
mx['visual']['query'] = {"queryState": {
    "Rows": {"projections": [cproj('DimDepartment', 'Department')]},
    "Columns": {"projections": [cproj('DimDate', 'Year')]},
    "Values": {"projections": [mproj('Vacation Days Used per Year')]}},
    "sortDefinition": {"sort": [{"field": col('DimDepartment', 'Department'), "direction": "Ascending"}], "isDefaultSort": True}}
bc = mx['visual']['objects']['values'][0]
bc['selector']['metadata'] = '_Measures.Vacation Days Used per Year'
bc['properties']['backColor']['solid']['color']['expr']['FillRule']['Input'] = meas('Vacation Days Used per Year')
mx['filterConfig'] = {"filters": [not_in('f_matrix_dept', 'DimDepartment', 'Department', 'Acme Corporation'),
    {"name": nid('f_matrix_year'), "field": col('DimDate', 'Year'), "type": "Advanced",
     "filter": {"Version": 2, "From": [{"Name": "d", "Entity": "DimDate", "Type": 0}],
                "Where": [{"Condition": {"Between": {"Expression": {"Column": {"Expression": {"SourceRef": {"Source": "d"}}, "Property": "Year"}},
                           "LowerBound": {"Literal": {"Value": "2024L"}}, "UpperBound": {"Literal": {"Value": "2026L"}}}}}]}}]}
titles(mx, 'Vacation days per employee', 'Working days by year; 2026 is up to the reference date',
       'Matrix: approved vacation working days per employee by department (rows) and year (columns), heat coloured.')
mx['position'].update(x=330, y=Y2, width=504.4, height=H2)
add('matrix', mx)

# 4 absent today (table; template: page 5 table without the level formatting)
tb = find(src5, 'tableEx')
tb['visual']['query'] = {"queryState": {"Values": {"projections": [
    cproj('DimEmployee', 'FullName', displayName='Employee'),
    cproj('DimDepartment', 'Department', displayName='Department'),
    cproj('DimLeaveType', 'LeaveType', displayName='Leave type'),
    cproj('FactLeaveRequests', 'StartDate', displayName='From'),
    cproj('FactLeaveRequests', 'EndDate', displayName='Until')]}},
    "sortDefinition": {"sort": [{"field": col('FactLeaveRequests', 'EndDate'), "direction": "Ascending"}]}}
ob = tb['visual']['objects']
ob['values'] = [o for o in ob.get('values', []) if 'selector' not in o]
ob.pop('columnWidth', None)
tb['filterConfig'] = {"filters": [bool_filter('f_absent', 'FactLeaveRequests', 'IsAbsentToday', 'true')]}
titles(tb, 'Absent today', {"expr": meas('Text: Absent Today')}, 'Table: employees on approved leave on the reference date with department, leave type and dates.')
tb['position'].update(x=858, y=Y2, width=1032, height=H2)
add('table', tb)

order = ['navbg', 'navtitle', 'navsub', 'nav', 'footer', 'info', 'title', 'subtitle', 'slicerDepartment', 'slicerJobLevel', 'slicerNationality',
         'kpiLeave Days YTD', 'kpiCurrently Absent', 'kpiVacation Days YTD per Employee', 'kpiPending Requests',
         'months', 'dept', 'matrix', 'table']
assert set(order) == set(out), set(out) ^ set(order)
for i, l in enumerate(order):
    out[l]['position'].update(z=1000 * (i + 1), tabOrder=1000 * (i + 1))
vd = os.path.join(P6, 'visuals')
if os.path.exists(vd): shutil.rmtree(vd)
for d in out.values():
    dd = os.path.join(vd, d['name']); os.makedirs(dd)
    json.dump(d, open(os.path.join(dd, 'visual.json'), 'w', encoding='utf-8'), indent=2)
print(len(out), 'visuals in', P6)
