"""Historical generator of page 2 (Organization), kept as a TEMPLATE only. The page was adjusted by hand afterwards; running it would overwrite those changes. Style source: page 1."""
import json, glob, copy, hashlib, os, shutil
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
base = os.path.join(REPO, 'Acme HR Demo.Report', 'definition', 'pages')
P1 = os.path.join(base, 'ff862ad3bc453005bb9c')
P2 = os.path.join(base, 'a0a5139c61208801d6f5')
L = lambda v: {"expr": {"Literal": {"Value": v}}}
SOL = lambda h: {"solid": {"color": L("'%s'" % h)}}
def nid(l): return hashlib.md5(('hr_dashboard|org|' + l).encode()).hexdigest()[:20]
src = [json.load(open(f, encoding='utf-8')) for f in glob.glob(os.path.join(P1, 'visuals', '*', 'visual.json'))]
SCHEMA = src[0]['$schema']
def find(t, x=None, y=None):
    for d in src:
        p = d['position']
        if d['visual']['visualType'] == t and (x is None or abs(p['x'] - x) < 3) and (y is None or abs(p['y'] - y) < 3):
            return copy.deepcopy(d)
    raise Exception((t, x, y))
out = {}
def add(label, d, x=None, y=None, w=None, h=None):
    d['name'] = nid(label)
    if x is not None: d['position'].update(x=x, y=y, width=w, height=h)
    out[label] = d
    return d
def alt(d, t):
    vc = d['visual'].setdefault('visualContainerObjects', {})
    vc['general'] = [{"properties": {"altText": L("'%s'" % t.replace("'", "''"))}}]
def meas(p): return {"Measure": {"Expression": {"SourceRef": {"Entity": "_Measures"}}, "Property": p}}
def col(p): return {"Column": {"Expression": {"SourceRef": {"Entity": "Employees"}}, "Property": p}}
def cproj(p): return {"field": col(p), "queryRef": "Employees." + p, "nativeQueryRef": p, "active": True}
def mproj(p): return {"field": meas(p), "queryRef": "_Measures." + p, "nativeQueryRef": p}

# ---- shell copied from page 1
for t, x, y, k in [('textbox', 0, 0, 'navbg'), ('textbox', 36, 36, 'navtitle'), ('textbox', 36, 84, 'navsub'),
                   ('pageNavigator', None, None, 'nav'), ('card', 0, None, 'footer'),
                   ('cardVisual', 317, 74, 'subtitle'), ('textbox', 330, 19, 'title')]:
    d = add(k, find(t, x, y))
    if k == 'title':
        d['visual']['objects']['general'][0]['properties']['paragraphs'][0]['textRuns'][0]['value'] = 'Organization'
        alt(d, 'Page title: Organization')
for x, k in [(1122, 'Department'), (1394, 'JobLevel'), (1637, 'Nationality')]:
    d = add('slicer' + k, find('slicer', x, 30))
    d['visual']['syncGroup'] = {"groupName": k, "fieldChanges": True, "filterChanges": True}

# ---- KPI cards
tpl = find('cardVisual', 329, 138)
def kpi(x, m, title, sub, alttext):
    d = copy.deepcopy(tpl); q = d['visual']['query']
    q['queryState']['Data']['projections'] = [mproj(m)]
    q['sortDefinition']['sort'][0]['field'] = meas(m)
    pr = d['visual']['visualContainerObjects']
    pr['title'][0]['properties']['text'] = L("'%s'" % title)
    pr['subTitle'][0]['properties']['text'] = L("'%s'" % sub[1]) if sub[0] == 'lit' else {"expr": meas(sub[1])}
    alt(d, alttext)
    add('kpi' + m, d, x, 137.5, 373.9, 139.7)
kpi(328.7, 'Managers', 'Managers', ('lit', 'With at least one direct report'), 'Managers: employees with at least one direct report')
kpi(726.2, 'Span of Control', 'Average span of control', ('lit', 'Direct reports per manager'), 'Average number of direct reports per manager')
kpi(1121.6, 'Largest Span of Control', 'Largest span of control', ('m', 'Text: Largest Span'), 'Largest number of direct reports of one manager')
kpi(1519.0, 'Departments at Target', 'Departments at target', ('m', 'Text: Departments at Target'), 'Departments whose headcount equals the plan')

# ---- charts
W, H = 504.4, 363.0
bar = find('barChart', 858, 300)
pos = find('barChart', 1386, 300)
def titles(d, t, s, at):
    vc = d['visual']['visualContainerObjects']
    vc['title'][0]['properties']['text'] = L("'%s'" % t)
    vc['subTitle'][0]['properties']['text'] = L("'%s'" % s)
    alt(d, at)

dt = {"$schema": SCHEMA, "name": '', "position": {"x": 330, "y": 300, "z": 1, "height": H, "width": W * 2 + 24, "tabOrder": 1},
      "visual": {"visualType": "decompositionTreeVisual",
                 "query": {"queryState": {"Analyze": {"projections": [mproj('Headcount')]},
                                           "ExplainBy": {"projections": [cproj(p) for p in ('Department', 'ManagerName', 'JobLevel')]}}},
                 "visualContainerObjects": copy.deepcopy(bar['visual']['visualContainerObjects']),
                 "drillFilterOtherVisuals": True}}
titles(dt, 'Reporting structure', 'Split headcount by department, manager or job level; click + to expand',
       'Decomposition tree: headcount split by department, manager and job level.')
add('dtree', dt)

d = copy.deepcopy(pos); q = d['visual']['query']
q['queryState']['Category']['projections'] = [cproj('FullName')]
q['queryState']['Y']['projections'] = [mproj('Direct Reports')]
q['sortDefinition']['sort'][0]['field'] = meas('Direct Reports')
fc = d['filterConfig']['filters'][0]
fc['name'] = nid('top15')
fc['field']['Column']['Property'] = 'FullName'
sq = fc['filter']['From'][0]['Expression']['Subquery']['Query']
sq['Select'][0]['Column']['Property'] = 'FullName'
sq['OrderBy'][0]['Expression']['Measure']['Property'] = 'Direct Reports'
sq['Top'] = 15
fc['filter']['Where'][0]['Condition']['In']['Expressions'][0]['Column']['Property'] = 'FullName'
titles(d, 'Direct reports per manager', 'Top 15 managers, coloured by department',
       'Bar chart: the 15 managers with the most direct reports, coloured by department.')
add('bar_span', d)

d = copy.deepcopy(bar); q = d['visual']['query']
q['queryState']['Category']['projections'] = [cproj('Department')]
q['queryState']['Y']['projections'] = [mproj('Target Headcount'), mproj('Department Headcount')]
q['sortDefinition']['sort'][0]['field'] = meas('Department Headcount')
d['visual']['objects']['dataPoint'] = [
    {"properties": {"fill": SOL('#CBD5E1')}, "selector": {"metadata": "_Measures.Target Headcount"}},
    {"properties": {"fill": SOL('#4A6FA5')}, "selector": {"metadata": "_Measures.Department Headcount"}}]
d['visual']['objects']['legend'] = [{"properties": {"show": L("true"), "position": L("'Bottom'"),
                                                      "fontSize": L("16D"), "labelColor": SOL('#1F2937')}}]
titles(d, 'Headcount vs target', 'Planned target (grey) and current headcount per department',
       'Clustered bar: target and actual headcount per department.')
add('bar_target', d)

tbl = {"$schema": SCHEMA, "name": '', "position": {"x": 858, "y": 687, "z": 1, "height": H, "width": W * 2 + 24, "tabOrder": 1},
       "visual": {"visualType": "tableEx",
                  "query": {"queryState": {"Values": {"projections": [cproj('Department'), mproj('Managers'), mproj('Span of Control'), mproj('Largest Span of Control')]}},
                            "sortDefinition": {"sort": [{"field": meas('Managers'), "direction": "Descending"}], "isDefaultSort": True}},
                  "objects": {"columnHeaders": [{"properties": {"fontFamily": L("'Segoe UI Semibold'"), "fontSize": L("16D"), "fontColor": SOL('#1F2937'), "backColor": SOL('#F3F4F6')}}],
                              "values": [{"properties": {"fontFamily": L("'Segoe UI'"), "fontSize": L("16D"), "fontColor": SOL('#1F2937')}}],
                              "grid": [{"properties": {"gridVertical": L("false"), "outlineColor": SOL('#E5E7EB')}}],
                              "total": [{"properties": {"fontSize": L("16D"), "fontFamily": L("'Segoe UI Semibold'")}}]},
                  "visualContainerObjects": copy.deepcopy(bar['visual']['visualContainerObjects']),
                  "drillFilterOtherVisuals": True}}
titles(tbl, 'Managers and span by department', 'Managers, average and largest span of control',
       'Table: managers, average and largest span of control per department.')
add('table', tbl)

# ---- layout: row 1 = tree (cols 1-2) + direct reports (col 3); row 2 = target (col 1) + table (cols 2-3)
def put(l, x, y, w, h): out[l]['position'].update(x=x, y=y, width=w, height=h)
put('dtree', 330, 300, W * 2 + 24, H); put('bar_span', 1386, 300, W, H)
put('bar_target', 330, 687, W, H); put('table', 858, 687, W * 2 + 24, H)
order = ['navbg', 'navtitle', 'navsub', 'nav', 'footer', 'title', 'subtitle', 'slicerDepartment', 'slicerJobLevel', 'slicerNationality',
         'kpiManagers', 'kpiSpan of Control', 'kpiLargest Span of Control', 'kpiDepartments at Target', 'dtree', 'bar_span', 'bar_target', 'table']
assert set(order) == set(out), set(out) ^ set(order)
for i, l in enumerate(order):
    out[l]['position'].update(z=1000 * (i + 1), tabOrder=1000 * (i + 1))
vd = os.path.join(P2, 'visuals')
if os.path.exists(vd): shutil.rmtree(vd)
for d in out.values():
    dd = os.path.join(vd, d['name']); os.makedirs(dd)
    json.dump(d, open(os.path.join(dd, 'visual.json'), 'w', encoding='utf-8'), indent=2)
print(len(out), 'visuals')
