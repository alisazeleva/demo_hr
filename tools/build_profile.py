"""Generator of page 7 (Employee profile, a hidden drill-through page): copies the shell, card, table and bar styles from the hand-adjusted pages 5 and 6.
Overwrites the page 7 visuals and page.json only. Run tools/validate_pbir.py afterwards."""
import json, glob, copy, hashlib, os, shutil
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
base = os.path.join(REPO, 'hr_dashboard.Report', 'definition', 'pages')
pages = {}
for f in glob.glob(os.path.join(base, '*', 'page.json')):
    pages[json.load(open(f, encoding='utf-8'))['displayName']] = os.path.dirname(f)
P5, P6, P7 = pages['Performance'], pages['Leave'], pages['Employee profile']
L = lambda v: {"expr": {"Literal": {"Value": v}}}
SOL = lambda h: {"solid": {"color": L("'%s'" % h)}}
def nid(l): return hashlib.md5(('hr_dashboard|profile|' + l).encode()).hexdigest()[:20]
def load(p): return [json.load(open(f, encoding='utf-8')) for f in glob.glob(os.path.join(p, 'visuals', '*', 'visual.json'))]
src5, src6 = load(P5), load(P6)
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
    d = add(k, find(src6, t, x, y))
    if k == 'title':
        d['visual']['objects']['general'][0]['properties']['paragraphs'][0]['textRuns'][0]['value'] = 'Employee profile'
        alt(d, 'Page title: Employee profile')

# ---- header cards (template: page 6 KPI card)
tpl = find(src6, 'cardVisual', 329, 138)
def card(label, x, w, m, title, sub, alttext, show_title=True):
    d = copy.deepcopy(tpl); q = d['visual']['query']
    q['queryState']['Data']['projections'] = [mproj(m)]
    q['sortDefinition']['sort'][0]['field'] = meas(m)
    vc = d['visual']['visualContainerObjects']
    vc['title'][0]['properties']['text'] = L("'%s'" % title)
    vc['subTitle'][0]['properties']['text'] = sub if isinstance(sub, dict) else L("'%s'" % sub)
    if not show_title:
        vc['title'][0]['properties']['show'] = L('false'); vc['subTitle'][0]['properties']['show'] = L('false')
    alt(d, alttext); d['position'].update(x=x, y=137.5, width=w, height=139.7)
    add(label, d)
card('photo', 330, 140, 'Text: Profile Initials', '', '', 'Profile picture placeholder showing the initials of the selected employee', show_title=False)
card('cName', 494, 334, 'Text: Profile Name', 'Employee', {"expr": meas('Text: Profile Job Level')}, 'Name and job level of the selected employee')
card('cDept', 848, 334, 'Text: Profile Department', 'Department', 'Current department', 'Department of the selected employee')
card('cMgr', 1202, 334, 'Text: Profile Manager', 'Manager', 'Direct manager', 'Direct manager of the selected employee')
card('cTenure', 1556, 334, 'Text: Profile Tenure', 'Tenure', {"expr": meas('Text: Profile Hire Date')}, 'Tenure and hire date of the selected employee')

# subtitle under the page title: employee number and position
sub = out['subtitle']
sub['visual']['query']['queryState']['Data']['projections'] = [mproj('Text: Profile Role')]
if 'sortDefinition' in sub['visual']['query']:
    sub['visual']['query']['sortDefinition']['sort'][0]['field'] = meas('Text: Profile Role')
alt(sub, 'Employee number and position of the selected employee')

# back button (action: Back)
back = {"$schema": SCHEMA, "name": '', "position": {"x": 1790, "y": 30, "z": 1, "height": 50, "width": 100, "tabOrder": 1},
        "visual": {"visualType": "actionButton",
                   "objects": {"icon": [{"properties": {"shapeType": L("'back'"), "lineColor": SOL('#1F2937')}, "selector": {"id": "default"}},
                                         {"properties": {"lineColor": SOL('#2563EB')}, "selector": {"id": "hover"}}],
                               "fill": [{"properties": {"show": L("false")}}]},
                   "visualContainerObjects": {"title": [{"properties": {"show": L("false")}}],
                                              "background": [{"properties": {"show": L("false")}}],
                                              "border": [{"properties": {"show": L("false")}}],
                                              "visualLink": [{"properties": {"show": L("true"), "type": L("'Back'")}}],
                                              "general": [{"properties": {"altText": L("'Back to the previous page'")}}]},
                   "drillFilterOtherVisuals": True}}
add('back', back)

W1, H1, Y1 = 504.4, 298.0, 300.0
Y2, H2 = 618.0, 432.0
barsrc = find(src5, 'barChart', 858, 300)         # neutral bar (hand-adjusted page 5)
VC = barsrc['visual']['visualContainerObjects']
AX = lambda **k: {"properties": dict({"labelColor": SOL('#1F2937'), "fontSize": L("14D"), "fontFamily": L("'Segoe UI'"), "showAxisTitle": L("false")}, **k)}

# 1 career timeline (table; template: page 6 table)
tb = find(src6, 'tableEx')
tb['visual']['query'] = {"queryState": {"Values": {"projections": [
    cproj('FactJobHistory', 'EffectiveDate', displayName='Date'),
    cproj('FactJobHistory', 'ChangeType', displayName='Change'),
    cproj('FactJobHistory', 'PositionTitle', displayName='Position'),
    cproj('FactJobHistory', 'Department', displayName='Department'),
    cproj('FactJobHistory', 'ManagerName', displayName='Manager')]}},
    "sortDefinition": {"sort": [{"field": col('FactJobHistory', 'EffectiveDate'), "direction": "Ascending"}]}}
tb.pop('filterConfig', None)
titles(tb, 'Career timeline', 'Job history from hire to today', 'Table: job history records with date, change type, position, department and manager.')
tb['position'].update(x=330, y=Y1, width=792, height=H1)
add('timeline', tb)

# 2 salary history (stepped line, reason and change in the tooltip)
ln = {"$schema": SCHEMA, "name": '', "position": {"x": 1146, "y": Y1, "z": 1, "height": H1, "width": 744, "tabOrder": 1},
      "visual": {"visualType": "lineChart",
                 "query": {"queryState": {"Category": {"projections": [cproj('FactCompensation', 'EffectiveDate')]},
                                           "Y": {"projections": [mproj('Base Salary')]},
                                           "Tooltips": {"projections": [cproj('FactCompensation', 'Reason', active=False),
                                                                        mproj('Salary Change')]}},
                           "sortDefinition": {"sort": [{"field": col('FactCompensation', 'EffectiveDate'), "direction": "Ascending"}]}},
                 "objects": {"dataPoint": [{"properties": {"fill": SOL('#4A6FA5')}}],
                             "lineStyles": [{"properties": {"strokeWidth": L("3L"), "showMarker": L("true"), "stepped": L("true")}}],
                             "labels": [{"properties": {"show": L("false")}}],
                             "categoryAxis": [AX(axisType=L("'Continuous'"))],
                             "valueAxis": [{"properties": {"labelColor": SOL('#5B6472'), "fontSize": L("14D"), "fontFamily": L("'Segoe UI'"),
                                                            "showAxisTitle": L("false"), "gridlineShow": L("true"), "gridlineColor": SOL('#E5E7EB')}}],
                             "general": [{"properties": {"responsive": L("false")}}]},
                 "visualContainerObjects": copy.deepcopy(VC), "drillFilterOtherVisuals": True}}
titles(ln, 'Salary history', 'EUR per year; hover a step for the reason and the change', 'Stepped line chart: base salary over time with the change reason in the tooltip.')
add('salary', ln)

# 3 reviews: rating by year
cc = {"$schema": SCHEMA, "name": '', "position": {"x": 330, "y": Y2, "z": 1, "height": H2, "width": 792, "tabOrder": 1},
      "visual": {"visualType": "columnChart",
                 "query": {"queryState": {"Category": {"projections": [cproj('FactReviews', 'ReviewYear')]},
                                           "Y": {"projections": [mproj('Average Rating')]}},
                           "sortDefinition": {"sort": [{"field": col('FactReviews', 'ReviewYear'), "direction": "Ascending"}]}},
                 "objects": {"dataPoint": [{"properties": {"fill": SOL('#4A6FA5')}}],
                             "labels": [{"properties": {"show": L("true"), "fontSize": L("17.25D"), "color": SOL('#1F2937'),
                                                        "fontFamily": L("'Segoe UI'"), "labelPosition": L("'OutsideEnd'")}}],
                             "categoryAxis": [AX(axisType=L("'Categorical'"))],
                             "valueAxis": [{"properties": {"show": L("false"), "gridlineShow": L("false"), "showAxisTitle": L("false"),
                                                            "start": L("0D"), "end": L("5D")}}],
                             "general": [{"properties": {"responsive": L("false")}}]},
                 "visualContainerObjects": copy.deepcopy(VC), "drillFilterOtherVisuals": True}}
titles(cc, 'Performance reviews', 'Annual rating by review year, scale 1 to 5', 'Column chart: performance rating per review year.')
add('reviews', cc)

# 4 leave summary: bar by type, last 24 months
d = copy.deepcopy(barsrc); q = d['visual']['query']
q['queryState']['Category']['projections'] = [cproj('DimLeaveType', 'LeaveType')]
q['queryState']['Y']['projections'] = [mproj('Leave Days Last 24 Months')]
q['sortDefinition'] = {"sort": [{"field": meas('Leave Days Last 24 Months'), "direction": "Descending"}], "isDefaultSort": True}
d.pop('filterConfig', None)
va = d['visual']['objects']['valueAxis'][0]['properties']; va.pop('start', None); va.pop('end', None)
titles(d, 'Leave summary', 'Approved working days by type, last 24 months', 'Bar chart: approved leave working days by leave type in the last 24 months.')
d['position'].update(x=1146, y=Y2, width=744, height=H2)
add('leave', d)

order = ['navbg', 'navtitle', 'navsub', 'nav', 'footer', 'info', 'title', 'subtitle', 'back',
         'photo', 'cName', 'cDept', 'cMgr', 'cTenure', 'timeline', 'salary', 'reviews', 'leave']
assert set(order) == set(out), set(out) ^ set(order)
for i, l in enumerate(order):
    out[l]['position'].update(z=1000 * (i + 1), tabOrder=1000 * (i + 1))
vd = os.path.join(P7, 'visuals')
if os.path.exists(vd): shutil.rmtree(vd)
for d in out.values():
    dd = os.path.join(vd, d['name']); os.makedirs(dd)
    json.dump(d, open(os.path.join(dd, 'visual.json'), 'w', encoding='utf-8'), indent=2)

# ---- page.json: hidden drill-through page filtered by the employee (FullName is unique)
pj = os.path.join(P7, 'page.json')
pg = json.load(open(pj, encoding='utf-8'))
fname = 'drill_' + hashlib.md5(b'hr_dashboard|profile|filter').hexdigest()[:16]
pg['filterConfig'] = {"filters": [{"name": fname, "field": col('DimEmployee', 'FullName'), "type": "Categorical", "howCreated": "Drillthrough"}]}
pg['pageBinding'] = {"name": 'bind_' + hashlib.md5(b'hr_dashboard|profile|binding').hexdigest()[:16], "type": "Drillthrough", "referenceScope": "Default",
                     "parameters": [{"name": 'Param_' + fname, "boundFilter": fname, "fieldExpr": col('DimEmployee', 'FullName')}]}
pg['visibility'] = 'HiddenInViewMode'
json.dump(pg, open(pj, 'w', encoding='utf-8'), indent=2)
print(len(out), 'visuals in', P7)
