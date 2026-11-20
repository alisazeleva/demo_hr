"""Generator of page 3 (Career): copies the shell (navigation, header, slicers, footer, KPI cards) from page 2 and adds the visuals. Overwrites the page 3 visuals. For a new page, copy this file, change the visuals, then run tools/validate_pbir.py."""
import json, glob, copy, hashlib, os, shutil
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
base = os.path.join(REPO, 'Acme HR Demo.Report', 'definition', 'pages')
pages = {}
for f in glob.glob(os.path.join(base, '*', 'page.json')):
    pages[json.load(open(f, encoding='utf-8'))['displayName']] = os.path.dirname(f)
P1, P2, P3 = pages['Workforce'], pages['Organization'], pages['Career']
L = lambda v: {"expr": {"Literal": {"Value": v}}}
SOL = lambda h: {"solid": {"color": L("'%s'" % h)}}
def nid(l): return hashlib.md5(('hr_dashboard|career|' + l).encode()).hexdigest()[:20]
def load(p): return [json.load(open(f, encoding='utf-8')) for f in glob.glob(os.path.join(p, 'visuals', '*', 'visual.json'))]
src2, src1 = load(P2), load(P1)
SCHEMA = src2[0]['$schema']
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

# ---- shell copied from page 2 (navigation, header, slicers, footer, info button)
for t, x, y, k in [('textbox', 0, 0, 'navbg'), ('textbox', 36, 36, 'navtitle'), ('textbox', 36, 84, 'navsub'),
                   ('pageNavigator', None, None, 'nav'), ('card', 0, None, 'footer'), ('actionButton', None, None, 'info'),
                   ('cardVisual', 317, 74, 'subtitle'), ('textbox', 330, 19, 'title')]:
    d = add(k, find(src2, t, x, y))
    if k == 'title':
        d['visual']['objects']['general'][0]['properties']['paragraphs'][0]['textRuns'][0]['value'] = 'Career'
        alt(d, 'Page title: Career')
for x, k in [(1122, 'Department'), (1394, 'JobLevel'), (1637, 'Nationality')]:
    add('slicer' + k, find(src2, 'slicer', x, 30))   # keeps the syncGroup of page 2

# ---- KPI cards (template: page 2 card)
tpl = find(src2, 'cardVisual', 329, 138)
def kpi(x, m, title, sub, alttext):
    d = copy.deepcopy(tpl); q = d['visual']['query']
    q['queryState']['Data']['projections'] = [mproj(m)]
    q['sortDefinition']['sort'][0]['field'] = meas(m)
    vc = d['visual']['visualContainerObjects']
    vc['title'][0]['properties']['text'] = L("'%s'" % title)
    vc['subTitle'][0]['properties']['text'] = L("'%s'" % sub)
    alt(d, alttext); d['position'].update(x=x, y=137.5, width=373.9, height=139.7)
    add('kpi' + m, d)
kpi(328.7, 'Promotions', 'Promotions', 'Including promotions with a transfer', 'Number of promotions')
kpi(726.2, 'Department Transfers', 'Department transfers', 'Including promotions with a transfer', 'Number of department transfers')
kpi(1121.6, 'Position Changes', 'Position changes', 'Without a promotion or transfer', 'Number of position changes')
kpi(1519.0, 'Manager Changes', 'Manager changes', 'Only the manager changed', 'Number of manager changes')

# ---- templates for charts
deptbar = None
for d in src1:
    v = d['visual']
    if v['visualType'] == 'barChart' and any(p['field'].get('Measure', {}).get('Property') == 'Department Headcount'
                                               for p in v['query']['queryState']['Y']['projections']):
        deptbar = copy.deepcopy(d)
assert deptbar
pivot = find(src2, 'pivotTable')
W, H = 504.4, 363.0
CT = ['Promotion', 'Promotion + Department Transfer', 'Department Transfer', 'Position Change', 'Manager Change']
CC = ['#2563EB', '#8FAEE8', '#4A6FA5', '#E0A030', '#5B6472']

# 1 career events per year: stacked column, change type as legend
vc = copy.deepcopy(deptbar['visual']['visualContainerObjects'])
col_chart = {"$schema": SCHEMA, "name": '', "position": {"x": 330, "y": 300, "z": 1, "height": H, "width": 1032, "tabOrder": 1},
             "visual": {"visualType": "columnChart",
                        "query": {"queryState": {"Category": {"projections": [cproj('DimDate', 'Year')]},
                                                  "Series": {"projections": [cproj('FactJobHistory', 'ChangeType')]},
                                                  "Y": {"projections": [mproj('Career Events')]}}},
                        "objects": {
                            "dataPoint": [{"properties": {"fill": SOL(c)},
                                           "selector": {"data": [{"scopeId": {"Comparison": {"ComparisonKind": 0,
                                               "Left": col('FactJobHistory', 'ChangeType'), "Right": {"Literal": {"Value": "'%s'" % n}}}}}]}}
                                          for n, c in zip(CT, CC)],
                            "labels": [{"properties": {"show": L("false")}}],
                            "legend": [{"properties": {"show": L("true"), "position": L("'Bottom'"), "fontSize": L("16D"),
                                                        "labelColor": SOL('#1F2937'), "fontFamily": L("'Segoe UI'")}}],
                            "categoryAxis": [{"properties": {"labelColor": SOL('#1F2937'), "fontSize": L("16D"), "fontFamily": L("'Segoe UI'"),
                                                              "showAxisTitle": L("false"), "axisType": L("'Categorical'")}}],
                            "valueAxis": [{"properties": {"labelColor": SOL('#5B6472'), "fontSize": L("16D"), "fontFamily": L("'Segoe UI'"),
                                                           "showAxisTitle": L("false"), "gridlineShow": L("true"),
                                                           "gridlineColor": SOL('#E5E7EB')}}],
                            "general": [{"properties": {"responsive": L("false")}}]},
                        "visualContainerObjects": vc, "drillFilterOtherVisuals": True}}
titles(col_chart, 'Career events per year', 'Changes after hire by type; the Initial Assignment at hire is not counted',
       'Stacked column chart: career events per year by change type.')
add('events', col_chart)

# 2 average months between promotions by department
d = copy.deepcopy(deptbar); q = d['visual']['query']
q['queryState']['Y']['projections'] = [mproj('Average Months Between Promotions')]
q['sortDefinition']['sort'][0]['field'] = meas('Average Months Between Promotions')
d['visual'].get('filterConfig')
d.pop('filterConfig', None)
titles(d, 'Months between promotions', {"expr": meas('Text: Months Between Promotions')},
       'Bar chart: average months between consecutive promotions per department.')
d['position'].update(x=1386, y=300, width=W, height=H)
add('months', d)

# 3 matrix: change type x department
mx = copy.deepcopy(pivot)
mx['visual']['query'] = {"queryState": {
    "Rows": {"projections": [cproj('FactJobHistory', 'ChangeType')]},
    "Columns": {"projections": [cproj('DimDepartment', 'Department')]},
    "Values": {"projections": [mproj('Career Events')]}},
    "sortDefinition": {"sort": [{"field": meas('Career Events'), "direction": "Descending"}], "isDefaultSort": True}}
mx['filterConfig'] = {"filters": [{"name": nid('f_matrix_dept'), "field": col('DimDepartment', 'Department'), "type": "Categorical",
    "filter": {"Version": 2, "From": [{"Name": "e", "Entity": "DimDepartment", "Type": 0}],
               "Where": [{"Condition": {"Not": {"Expression": {"In": {"Expressions": [{"Column": {"Expression": {"SourceRef": {"Source": "e"}}, "Property": "Department"}}],
                          "Values": [[{"Literal": {"Value": "'Acme Corporation'"}}]]}}}}}]},
    "objects": {"general": [{"properties": {"isInvertedSelectionMode": L("true")}}]}}]}
mx['visual']['visualContainerObjects']['subTitle'][0]['properties']['show'] = L('true')
titles(mx, 'Changes by type and department', 'Number of career events; department is the current department',
       'Matrix: career events by change type (rows) and current department (columns).')
mx['visual']['visualContainerObjects']['border'] = copy.deepcopy(deptbar['visual']['visualContainerObjects']['border'])
mx['visual']['visualContainerObjects']['background'] = copy.deepcopy(deptbar['visual']['visualContainerObjects']['background'])
mx['visual']['visualContainerObjects']['title'] = copy.deepcopy(deptbar['visual']['visualContainerObjects']['title'])
titles(mx, 'Changes by type and department', 'Number of career events; department is the current department',
       'Matrix: career events by change type (rows) and current department (columns).')
mx['position'].update(x=330, y=687, width=792, height=H)
add('matrix', mx)

# 4 latest career moves: table
tb = {"$schema": SCHEMA, "name": '', "position": {"x": 1146, "y": 687, "z": 1, "height": H, "width": 744, "tabOrder": 1},
      "visual": {"visualType": "tableEx",
                 "query": {"queryState": {"Values": {"projections": [
                     cproj('DimEmployee', 'FullName', displayName='Employee'),
                     cproj('FactJobHistory', 'EffectiveDate', displayName='Date'),
                     cproj('FactJobHistory', 'ChangeType', displayName='Change'),
                     cproj('FactJobHistory', 'PrevPositionTitle', displayName='From position'),
                     cproj('FactJobHistory', 'PositionTitle', displayName='To position')]}},
                           "sortDefinition": {"sort": [{"field": col('FactJobHistory', 'EffectiveDate'), "direction": "Descending"}]}},
                 "objects": {"columnHeaders": [{"properties": {"fontFamily": L("'Segoe UI Semibold'"), "fontSize": L("16D"), "fontColor": SOL('#1F2937'), "outlineStyle": L("4D")}}],
                             "values": [{"properties": {"fontFamily": L("'Segoe UI'"), "fontSize": L("16D"), "fontColor": SOL('#1F2937')}}],
                             "grid": [{"properties": {"gridVertical": L("false"), "gridHorizontal": L("true"), "outlineColor": SOL('#E5E7EB')}}]},
                 "visualContainerObjects": copy.deepcopy(deptbar['visual']['visualContainerObjects']), "drillFilterOtherVisuals": True},
      "filterConfig": {"filters": [{"name": nid('f_table_type'), "field": col('FactJobHistory', 'ChangeType'), "type": "Categorical",
          "filter": {"Version": 2, "From": [{"Name": "f", "Entity": "FactJobHistory", "Type": 0}],
                     "Where": [{"Condition": {"Not": {"Expression": {"In": {"Expressions": [{"Column": {"Expression": {"SourceRef": {"Source": "f"}}, "Property": "ChangeType"}}],
                                "Values": [[{"Literal": {"Value": "'Initial Assignment'"}}]]}}}}}]},
          "objects": {"general": [{"properties": {"isInvertedSelectionMode": L("true")}}]}}]}}
titles(tb, 'Latest career moves', 'Newest first, excluding the Initial Assignment at hire',
       'Table: latest career moves with employee, date, change type, previous and new position.')
add('table', tb)

# ---- z and tab order (reading order)
order = ['navbg', 'navtitle', 'navsub', 'nav', 'footer', 'info', 'title', 'subtitle', 'slicerDepartment', 'slicerJobLevel', 'slicerNationality',
         'kpiPromotions', 'kpiDepartment Transfers', 'kpiPosition Changes', 'kpiManager Changes', 'events', 'months', 'matrix', 'table']
assert set(order) == set(out), set(out) ^ set(order)
for i, l in enumerate(order):
    out[l]['position'].update(z=1000 * (i + 1), tabOrder=1000 * (i + 1))
vd = os.path.join(P3, 'visuals')
if os.path.exists(vd): shutil.rmtree(vd)
for d in out.values():
    dd = os.path.join(vd, d['name']); os.makedirs(dd)
    json.dump(d, open(os.path.join(dd, 'visual.json'), 'w', encoding='utf-8'), indent=2)
print(len(out), 'visuals in', P3)
