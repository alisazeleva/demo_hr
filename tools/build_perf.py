"""Generator of page 5 (Performance): copies the shell and chart styles from page 4 and the matrix and table from page 3, then adds the visuals.
Overwrites the page 5 visuals only. Run tools/validate_pbir.py afterwards."""
import json, glob, copy, hashlib, os, shutil
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
base = os.path.join(REPO, 'hr_dashboard.Report', 'definition', 'pages')
pages = {}
for f in glob.glob(os.path.join(base, '*', 'page.json')):
    pages[json.load(open(f, encoding='utf-8'))['displayName']] = os.path.dirname(f)
P1, P2, P3, P4, P5 = pages['Workforce'], pages['Organization'], pages['Career'], pages['Compensation'], pages['Performance']
L = lambda v: {"expr": {"Literal": {"Value": v}}}
SOL = lambda h: {"solid": {"color": L("'%s'" % h)}}
def nid(l): return hashlib.md5(('hr_dashboard|performance|' + l).encode()).hexdigest()[:20]
def load(p): return [json.load(open(f, encoding='utf-8')) for f in glob.glob(os.path.join(p, 'visuals', '*', 'visual.json'))]
src3, src1, src4, src2 = load(P3), load(P1), load(P4), load(P2)
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
    d = add(k, find(src4, t, x, y))
    if k == 'title':
        d['visual']['objects']['general'][0]['properties']['paragraphs'][0]['textRuns'][0]['value'] = 'Performance'
        alt(d, 'Page title: Performance')
for x, k in [(1122, 'Department'), (1394, 'JobLevel'), (1637, 'Nationality')]:
    add('slicer' + k, find(src4, 'slicer', x, 30))

# ---- KPI cards (template: page 4 card)
tpl = find(src4, 'cardVisual', 329, 138)
def kpi(x, m, title, sub, alttext):
    d = copy.deepcopy(tpl); q = d['visual']['query']
    q['queryState']['Data']['projections'] = [mproj(m)]
    q['sortDefinition']['sort'][0]['field'] = meas(m)
    vc = d['visual']['visualContainerObjects']
    vc['title'][0]['properties']['text'] = L("'%s'" % title)
    vc['subTitle'][0]['properties']['text'] = L("'%s'" % sub)
    alt(d, alttext); d['position'].update(x=x, y=137.5, width=373.9, height=139.7)
    add('kpi' + m, d)
kpi(328.7, 'Average Rating', 'Average rating', 'All reviews, scale 1 to 5', 'Average performance rating of all reviews')
kpi(726.2, 'Exceeds or Outstanding Share', 'Exceeds or Outstanding', 'Share of latest reviews', 'Share of latest reviews rated Exceeds Expectations or Outstanding')
kpi(1121.6, 'Employees Without Recent Review', 'Without a recent review', 'No review in the last 12 months', 'Employees without a review in the last 12 months')
kpi(1519.0, 'Number of Reviews', 'Reviews', 'Annual reviews, 2012 to 2025', 'Number of annual performance reviews')

H = 363.0
AX = lambda **k: {"properties": dict({"labelColor": SOL('#1F2937'), "fontSize": L("16D"), "fontFamily": L("'Segoe UI'"), "showAxisTitle": L("false")}, **k)}
deptbar = find(src4, 'barChart', 330, 300)       # department colours (hand-adjusted page 4)
levelbar = find(src4, 'barChart', 858, 300)      # neutral bar
VC = deptbar['visual']['visualContainerObjects']
AX5 = {"start": L("0D"), "end": L("5D")}

# 1 average rating by department
d = copy.deepcopy(deptbar); q = d['visual']['query']
q['queryState']['Y']['projections'] = [mproj('Average Rating')]
q['sortDefinition']['sort'][0]['field'] = meas('Average Rating')
d['filterConfig'] = {"filters": [not_in('f_dept', 'DimDepartment', 'Department', 'Acme Corporation')]}
d['visual']['objects']['valueAxis'][0]['properties'].update(AX5)
titles(d, 'Average rating by department', 'All reviews, scale 1 to 5; current department', 'Bar chart: average performance rating per department.')
d['position'].update(x=330, y=300, width=504.4, height=H)
add('dept', d)

# 2 average rating by manager (reviewer), top 10
d = copy.deepcopy(levelbar); q = d['visual']['query']
q['queryState']['Category']['projections'] = [cproj('FactReviews', 'ReviewerName')]
q['queryState']['Y']['projections'] = [mproj('Average Rating')]
q['sortDefinition'] = {"sort": [{"field": meas('Average Rating'), "direction": "Descending"}], "isDefaultSort": True}
d['visual']['objects']['valueAxis'][0]['properties'].update(AX5)
d['filterConfig'] = {"filters": [{"name": nid('f_top10'), "field": col('FactReviews', 'ReviewerName'), "type": "TopN",
    "filter": {"Version": 2,
               "From": [{"Name": "subquery", "Expression": {"Subquery": {"Query": {"Version": 2,
                            "From": [{"Name": "f", "Entity": "FactReviews", "Type": 0}, {"Name": "m", "Entity": "_Measures", "Type": 0}],
                            "Select": [{"Column": {"Expression": {"SourceRef": {"Source": "f"}}, "Property": "ReviewerName"}, "Name": "field"}],
                            "OrderBy": [{"Direction": 2, "Expression": {"Measure": {"Expression": {"SourceRef": {"Source": "m"}}, "Property": "Average Rating"}}}],
                            "Top": 10}}}, "Type": 2},
                        {"Name": "f", "Entity": "FactReviews", "Type": 0}],
               "Where": [{"Condition": {"In": {"Expressions": [{"Column": {"Expression": {"SourceRef": {"Source": "f"}}, "Property": "ReviewerName"}}],
                                                "Table": {"SourceRef": {"Source": "subquery"}}}}}]}}]}
titles(d, 'Average rating by manager', 'Top 10 managers by the average rating they gave', 'Bar chart: top 10 managers by average rating given in their reviews.')
d['position'].update(x=858, y=300, width=504.4, height=H)
add('manager', d)

# 3 rating distribution: column by level (sorted by Level Order)
cc = {"$schema": SCHEMA, "name": '', "position": {"x": 1386, "y": 300, "z": 1, "height": H, "width": 504.4, "tabOrder": 1},
      "visual": {"visualType": "columnChart",
                 "query": {"queryState": {"Category": {"projections": [cproj('FactReviews', 'Level')]},
                                           "Y": {"projections": [mproj('Number of Reviews')]}},
                           "sortDefinition": {"sort": [{"field": col('FactReviews', 'Level'), "direction": "Ascending"}]}},
                 "objects": {"dataPoint": [{"properties": {"fill": SOL('#4A6FA5')}}],
                             "labels": [{"properties": {"show": L("true"), "fontSize": L("17.25D"), "color": SOL('#1F2937'),
                                                        "fontFamily": L("'Segoe UI'"), "labelPosition": L("'OutsideEnd'")}}],
                             "categoryAxis": [AX(fontSize=L("14D"), axisType=L("'Categorical'"))],
                             "valueAxis": [{"properties": {"show": L("false"), "gridlineShow": L("false"), "showAxisTitle": L("false")}}],
                             "general": [{"properties": {"responsive": L("false")}}]},
                 "visualContainerObjects": copy.deepcopy(VC), "drillFilterOtherVisuals": True}}
titles(cc, 'Rating distribution', 'Number of reviews by performance level', 'Column chart: number of reviews per performance level.')
add('distribution', cc)

# 4 matrix with heat colouring (template: page 3 matrix)
mx = find(src2, 'pivotTable')   # page 2 matrix style; heat colouring added below
mx['visual']['query'] = {"queryState": {
    "Rows": {"projections": [cproj('DimDepartment', 'Department')]},
    "Columns": {"projections": [cproj('FactReviews', 'ReviewYear')]},
    "Values": {"projections": [mproj('Average Rating')]}},
    "sortDefinition": {"sort": [{"field": col('DimDepartment', 'Department'), "direction": "Ascending"}], "isDefaultSort": True}}
grad = {"FillRule": {"Input": meas('Average Rating'),
                     "FillRule": {"linearGradient2": {"min": {"color": {"Literal": {"Value": "'#b7c5db'"}}}, "max": {"color": {"Literal": {"Value": "'#6e8cb7'"}}},
                                                      "nullColoringStrategy": {"strategy": {"Literal": {"Value": "'noColor'"}}}}}}}
mx['visual']['objects']['values'] = [{"properties": {"backColor": {"solid": {"color": {"expr": grad}}}},
                                      "selector": {"data": [{"dataViewWildcard": {"matchingOption": 1}}], "metadata": "_Measures.Average Rating"}}]
mx['filterConfig'] = {"filters": [not_in('f_matrix_dept', 'DimDepartment', 'Department', 'Acme Corporation'),
    {"name": nid('f_matrix_year'), "field": col('FactReviews', 'ReviewYear'), "type": "Advanced",
     "filter": {"Version": 2, "From": [{"Name": "r", "Entity": "FactReviews", "Type": 0}],
                "Where": [{"Condition": {"Between": {"Expression": {"Column": {"Expression": {"SourceRef": {"Source": "r"}}, "Property": "ReviewYear"}},
                           "LowerBound": {"Literal": {"Value": "2018L"}}, "UpperBound": {"Literal": {"Value": "2025L"}}}}}]}}]}
titles(mx, 'Rating by department and year', 'Average rating, review years 2018 to 2025; darker is higher',
       'Matrix: average rating by department (rows) and review year (columns), heat coloured.')
mx['position'].update(x=330, y=687, width=792, height=H)
add('matrix', mx)

# 5 latest review per employee (template: page 3 table)
tb = find(src3, 'tableEx')
tb['visual']['query'] = {"queryState": {"Values": {"projections": [
    cproj('DimEmployee', 'FullName', displayName='Employee'),
    cproj('DimDepartment', 'Department', displayName='Department'),
    cproj('DimEmployee', 'LatestReviewDate', displayName='Review date'),
    cproj('DimEmployee', 'LatestRating', displayName='Rating'),
    cproj('DimEmployee', 'LatestPerformanceLevel', displayName='Level')]}},
    "sortDefinition": {"sort": [{"field": col('DimEmployee', 'LatestRating'), "direction": "Descending"}]}}
tb['visual']['objects']['values'] = tb['visual']['objects'].get('values', []) + [
    {"properties": {"backColor": {"solid": {"color": {"expr": meas('Level Colour')}}}},
     "selector": {"data": [{"dataViewWildcard": {"matchingOption": 1}}], "metadata": "DimEmployee.LatestPerformanceLevel"}}]
tb['filterConfig'] = {"filters": [not_in('f_table_blank', 'DimEmployee', 'LatestPerformanceLevel', 'null')]}
titles(tb, 'Latest review per employee', {"expr": meas('Text: Latest Reviews')}, 'Table: latest review per employee with department, date, rating and level.')
tb['position'].update(x=1146, y=687, width=744, height=H)
add('table', tb)

order = ['navbg', 'navtitle', 'navsub', 'nav', 'footer', 'info', 'title', 'subtitle', 'slicerDepartment', 'slicerJobLevel', 'slicerNationality',
         'kpiAverage Rating', 'kpiExceeds or Outstanding Share', 'kpiEmployees Without Recent Review', 'kpiNumber of Reviews',
         'dept', 'manager', 'distribution', 'matrix', 'table']
assert set(order) == set(out), set(out) ^ set(order)
for i, l in enumerate(order):
    out[l]['position'].update(z=1000 * (i + 1), tabOrder=1000 * (i + 1))
vd = os.path.join(P5, 'visuals')
if os.path.exists(vd): shutil.rmtree(vd)
for d in out.values():
    dd = os.path.join(vd, d['name']); os.makedirs(dd)
    json.dump(d, open(os.path.join(dd, 'visual.json'), 'w', encoding='utf-8'), indent=2)
print(len(out), 'visuals in', P5)
