"""Generator of page 4 (Compensation): copies the shell (navigation, header, slicers, footer, KPI cards) from page 3 and adds the visuals.
Overwrites the page 4 visuals only. Run tools/validate_pbir.py afterwards."""
import json, glob, copy, hashlib, os, shutil
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
base = os.path.join(REPO, 'hr_dashboard.Report', 'definition', 'pages')
pages = {}
for f in glob.glob(os.path.join(base, '*', 'page.json')):
    pages[json.load(open(f, encoding='utf-8'))['displayName']] = os.path.dirname(f)
P1, P3, P4 = pages['Workforce'], pages['Career'], pages['Compensation']
L = lambda v: {"expr": {"Literal": {"Value": v}}}
SOL = lambda h: {"solid": {"color": L("'%s'" % h)}}
def nid(l): return hashlib.md5(('hr_dashboard|compensation|' + l).encode()).hexdigest()[:20]
def load(p): return [json.load(open(f, encoding='utf-8')) for f in glob.glob(os.path.join(p, 'visuals', '*', 'visual.json'))]
src3, src1 = load(P3), load(P1)
SCHEMA = src3[0]['$schema']
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
    d = add(k, find(src3, t, x, y))
    if k == 'title':
        d['visual']['objects']['general'][0]['properties']['paragraphs'][0]['textRuns'][0]['value'] = 'Compensation'
        alt(d, 'Page title: Compensation')
for x, k in [(1122, 'Department'), (1394, 'JobLevel'), (1637, 'Nationality')]:
    add('slicer' + k, find(src3, 'slicer', x, 30))

# ---- KPI cards (template: page 3 card)
tpl = find(src3, 'cardVisual', 329, 138)
def kpi(x, m, title, sub, alttext):
    d = copy.deepcopy(tpl); q = d['visual']['query']
    q['queryState']['Data']['projections'] = [mproj(m)]
    q['sortDefinition']['sort'][0]['field'] = meas(m)
    vc = d['visual']['visualContainerObjects']
    vc['title'][0]['properties']['text'] = L("'%s'" % title)
    vc['subTitle'][0]['properties']['text'] = L("'%s'" % sub)
    alt(d, alttext); d['position'].update(x=x, y=137.5, width=373.9, height=139.7)
    add('kpi' + m, d)
kpi(328.7, 'Average Salary', 'Average salary', 'EUR per year, current', 'Average current annual salary in EUR')
kpi(726.2, 'Median Salary', 'Median salary', 'EUR per year, current', 'Median current annual salary in EUR')
kpi(1121.6, 'Total Payroll', 'Total annual payroll', 'EUR per year, current salaries', 'Total annual payroll in EUR')
kpi(1519.0, 'Average Promotion Increase', 'Average promotion increase', 'Share of the previous salary', 'Average salary increase at a promotion')

# ---- chart templates
deptbar = None
for d in src1:
    v = d['visual']
    if v['visualType'] == 'barChart' and any(p['field'].get('Measure', {}).get('Property') == 'Department Headcount'
                                               for p in v['query']['queryState']['Y']['projections']):
        deptbar = copy.deepcopy(d)
levelbar = None
for d in src1:
    v = d['visual']
    if v['visualType'] == 'barChart' and any(p['field'].get('Column', {}).get('Property') == 'JobLevel'
                                               for p in v['query']['queryState']['Category']['projections']):
        levelbar = copy.deepcopy(d)
assert deptbar and levelbar
H = 363.0
VC = deptbar['visual']['visualContainerObjects']
AX = lambda **k: {"properties": dict({"labelColor": SOL('#1F2937'), "fontSize": L("16D"), "fontFamily": L("'Segoe UI'"),
                                      "showAxisTitle": L("false")}, **k)}
LEG = {"properties": {"show": L("true"), "position": L("'Bottom'"), "fontSize": L("16D"), "labelColor": SOL('#1F2937'), "fontFamily": L("'Segoe UI'")}}

# 1 average salary by department (department colours, Acme Corporation = CEO excluded)
d = copy.deepcopy(deptbar); q = d['visual']['query']
q['queryState']['Y']['projections'] = [mproj('Average Salary')]
q['sortDefinition']['sort'][0]['field'] = meas('Average Salary')
d['filterConfig'] = {"filters": [not_in('f_dept', 'DimDepartment', 'Department', 'Acme Corporation')]}
titles(d, 'Average salary by department', 'EUR per year, excluding the CEO', 'Bar chart: average current salary per department in EUR.')
d['position'].update(x=330, y=300, width=504.4, height=H)
add('dept', d)

# 2 average salary by job level
d = copy.deepcopy(levelbar); q = d['visual']['query']
q['queryState']['Y']['projections'] = [mproj('Average Salary')]
titles(d, 'Average salary by job level', 'EUR per year, most senior level first', 'Bar chart: average current salary per job level in EUR.')
d['position'].update(x=858, y=300, width=504.4, height=H)
d.pop('filterConfig', None)
add('level', d)

# 3 average salary by gender within level (clustered bar)
gb = {"$schema": SCHEMA, "name": '', "position": {"x": 1386, "y": 300, "z": 1, "height": H, "width": 504.4, "tabOrder": 1},
      "visual": {"visualType": "clusteredBarChart",
                 "query": {"queryState": {"Category": {"projections": [cproj('DimPosition', 'JobLevel')]},
                                           "Series": {"projections": [cproj('DimEmployee', 'Gender')]},
                                           "Y": {"projections": [mproj('Average Salary')]}},
                           "sortDefinition": {"sort": [{"field": col('DimPosition', 'JobLevel'), "direction": "Ascending"}]}},
                 "objects": {"dataPoint": [{"properties": {"fill": SOL(c)},
                                            "selector": {"data": [{"scopeId": {"Comparison": {"ComparisonKind": 0,
                                                "Left": col('DimEmployee', 'Gender'), "Right": {"Literal": {"Value": "'%s'" % n}}}}}]}}
                                           for n, c in [('Female', '#7C5CD6'), ('Male', '#E0A030')]],
                             "labels": [{"properties": {"show": L("true"), "fontSize": L("14D"), "color": SOL('#1F2937'),
                                                        "fontFamily": L("'Segoe UI'"), "labelPosition": L("'OutsideEnd'")}}],
                             "legend": [LEG],
                             "categoryAxis": [AX(show=L("true"), innerPadding=L("20L"))],
                             "valueAxis": [{"properties": {"show": L("false"), "gridlineShow": L("false"), "showAxisTitle": L("false")}}],
                             "general": [{"properties": {"responsive": L("false")}}]},
                 "visualContainerObjects": copy.deepcopy(VC), "drillFilterOtherVisuals": True},
      "filterConfig": {"filters": [not_in('f_gender_level', 'DimPosition', 'JobLevel', 'CEO')]}}
titles(gb, 'Salary by gender within level', 'EUR per year, excluding the CEO (fairness check)',
       'Clustered bar chart: average current salary by job level and gender in EUR.')
add('gender', gb)

# 4 average salary at year end: line
ln = {"$schema": SCHEMA, "name": '', "position": {"x": 330, "y": 687, "z": 1, "height": H, "width": 792, "tabOrder": 1},
      "visual": {"visualType": "lineChart",
                 "query": {"queryState": {"Category": {"projections": [cproj('DimDate', 'Year')]},
                                           "Y": {"projections": [mproj('Average Salary at Year End')]}}},
                 "objects": {"dataPoint": [{"properties": {"fill": SOL('#4A6FA5')}}],
                             "lineStyles": [{"properties": {"strokeWidth": L("3L"), "showMarker": L("true")}}],
                             "labels": [{"properties": {"show": L("false")}}],
                             "categoryAxis": [AX(axisType=L("'Categorical'"))],
                             "valueAxis": [{"properties": {"labelColor": SOL('#5B6472'), "fontSize": L("16D"), "fontFamily": L("'Segoe UI'"),
                                                            "showAxisTitle": L("false"), "gridlineShow": L("true"), "gridlineColor": SOL('#E5E7EB')}}],
                             "general": [{"properties": {"responsive": L("false")}}]},
                 "visualContainerObjects": copy.deepcopy(VC), "drillFilterOtherVisuals": True},
      "filterConfig": {"filters": [{"name": nid('f_year'), "field": col('DimDate', 'Year'), "type": "Advanced",
          "filter": {"Version": 2, "From": [{"Name": "d", "Entity": "DimDate", "Type": 0}],
                     "Where": [{"Condition": {"Between": {"Expression": {"Column": {"Expression": {"SourceRef": {"Source": "d"}}, "Property": "Year"}},
                                "LowerBound": {"Literal": {"Value": "2012L"}}, "UpperBound": {"Literal": {"Value": "2026L"}}}}}]}}]}}
titles(ln, 'Average salary over time', 'EUR per year, employees on payroll at year end (reference date for 2026)',
       'Line chart: average annual salary of employees employed at each year end, in EUR.')
add('line', ln)

# 5 increases by year: clustered column
cc = {"$schema": SCHEMA, "name": '', "position": {"x": 1146, "y": 687, "z": 1, "height": H, "width": 744, "tabOrder": 1},
      "visual": {"visualType": "clusteredColumnChart",
                 "query": {"queryState": {"Category": {"projections": [cproj('DimDate', 'Year')]},
                                           "Y": {"projections": [mproj('Average Annual Increase'), mproj('Average Promotion Increase')]}}},
                 "objects": {"dataPoint": [{"properties": {"fill": SOL('#4A6FA5')}, "selector": {"metadata": "_Measures.Average Annual Increase"}},
                                           {"properties": {"fill": SOL('#2563EB')}, "selector": {"metadata": "_Measures.Average Promotion Increase"}}],
                             "labels": [{"properties": {"show": L("false")}}],
                             "legend": [LEG],
                             "categoryAxis": [AX(axisType=L("'Categorical'"))],
                             "valueAxis": [{"properties": {"labelColor": SOL('#5B6472'), "fontSize": L("16D"), "fontFamily": L("'Segoe UI'"),
                                                            "showAxisTitle": L("false"), "gridlineShow": L("true"), "gridlineColor": SOL('#E5E7EB')}}],
                             "general": [{"properties": {"responsive": L("false")}}]},
                 "visualContainerObjects": copy.deepcopy(VC), "drillFilterOtherVisuals": True},
      "filterConfig": {"filters": [{"name": nid('f_year2'), "field": col('DimDate', 'Year'), "type": "Advanced",
          "filter": {"Version": 2, "From": [{"Name": "d", "Entity": "DimDate", "Type": 0}],
                     "Where": [{"Condition": {"Between": {"Expression": {"Column": {"Expression": {"SourceRef": {"Source": "d"}}, "Property": "Year"}},
                                "LowerBound": {"Literal": {"Value": "2013L"}}, "UpperBound": {"Literal": {"Value": "2026L"}}}}}]}}]}}
titles(cc, 'Salary increases by year', {"expr": meas('Text: Promotion Increase')},
       'Clustered column chart: average annual increase and average promotion increase per year, in percent.')
add('increases', cc)

order = ['navbg', 'navtitle', 'navsub', 'nav', 'footer', 'info', 'title', 'subtitle', 'slicerDepartment', 'slicerJobLevel', 'slicerNationality',
         'kpiAverage Salary', 'kpiMedian Salary', 'kpiTotal Payroll', 'kpiAverage Promotion Increase', 'dept', 'level', 'gender', 'line', 'increases']
assert set(order) == set(out), set(out) ^ set(order)
for i, l in enumerate(order):
    out[l]['position'].update(z=1000 * (i + 1), tabOrder=1000 * (i + 1))
vd = os.path.join(P4, 'visuals')
if os.path.exists(vd): shutil.rmtree(vd)
for d in out.values():
    dd = os.path.join(vd, d['name']); os.makedirs(dd)
    json.dump(d, open(os.path.join(dd, 'visual.json'), 'w', encoding='utf-8'), indent=2)
print(len(out), 'visuals in', P4)
