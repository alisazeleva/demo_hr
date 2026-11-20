"""First draft of page 0 (Home), built from desing/0 Home@1x.png (1280 x 720, every size x 1.5 on the 1920 x 1080 page).
The left menu and the info pop-up are copied from the Workforce page. Like the other build_*.py scripts this is a first draft:
do not re-run it over a page that was adjusted by hand in Desktop (it deletes and rewrites the whole Home page).
Usage: python tools/build_home.py
"""
import copy
import glob
import json
import os
import secrets
import shutil

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEF = os.path.join(REPO, 'Acme HR Demo.Report', 'definition')
PAGES = os.path.join(DEF, 'pages')
SCHEMA = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.14.0/schema.json'
WORKFORCE = 'ff862ad3bc453005bb9c'
HOME = 'e3a91c5d7b2f4086a1c4'   # fixed id, so the script can be re-run

NAVY, ACCENT, TEXT, MUTED, LIGHT = '#14213D', '#2563EB', '#1F2937', '#5B6472', '#CBD5E1'


def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def dump(path, doc):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(json.dumps(doc, indent=2, ensure_ascii=False))


def lit(value):
    return {'expr': {'Literal': {'Value': value}}}


def color(hex_):
    return {'solid': {'color': lit(f"'{hex_}'")}}


def container(alt, background=None, border=None, radius=15, link=None):
    """visualContainerObjects: no title or header; optional white or coloured background, border and link."""
    c = {'title': [{'properties': {'show': lit('false')}}],
         'visualHeader': [{'properties': {'show': lit('false')}}],
         'general': [{'properties': {'altText': lit(f"'{alt}'")}}]}
    c['background'] = [{'properties': {'show': lit('true'), 'color': color(background), 'transparency': lit('0D')}}] if background \
        else [{'properties': {'show': lit('false')}}]
    c['border'] = [{'properties': {'show': lit('true'), 'color': color(border), 'radius': lit(f'{radius}D'), 'width': lit('1.5D')}}] if border \
        else [{'properties': {'show': lit('false')}}]
    if link:
        c['visualLink'] = [{'properties': {'show': lit('true'), 'type': lit("'PageNavigation'"), 'navigationSection': lit(f"'{link}'")}}]
    return c


class Page:
    def __init__(self):
        self.visuals = []   # (name, visual dict); z and tab order follow the order of creation

    def add(self, x, y, w, h, visual, container_objects, hidden=False):
        name = secrets.token_hex(10)
        self.visuals.append((name, dict(x=x, y=y, w=w, h=h, visual=visual, container=container_objects, hidden=hidden)))
        return name

    def textbox(self, x, y, w, h, paragraphs, alt, background=None, border=None, radius=15):
        """paragraphs: list of paragraphs, each a list of (text, style dict) runs."""
        paras = [{'textRuns': [{'value': t, **({'textStyle': s} if s else {})} for t, s in runs]} for runs in paragraphs]
        v = {'visualType': 'textbox', 'objects': {'general': [{'properties': {'paragraphs': paras}}]}}
        return self.add(x, y, w, h, v, container(alt, background, border, radius))

    def rect(self, x, y, w, h, fill, alt, border=None, radius=15):
        return self.textbox(x, y, w, h, [[('', None)]], alt, background=fill, border=border or fill, radius=radius)

    def shape_text(self, x, y, w, h, tile, fill, text_props, alt, text_expr):
        v = {'visualType': 'shape', 'objects': {
            'shape': [{'properties': {'tileShape': lit(f"'{tile}'")}}],
            'rotation': [{'properties': {'shapeAngle': lit('0L')}}],
            'fill': [{'properties': {'show': lit('true'), 'fillColor': color(fill)}}] if fill else [{'properties': {'show': lit('false')}}],
            'outline': [{'properties': {'show': lit('false')}}],
            'text': [{'properties': {'show': lit('true')}}, {'properties': {'text': text_expr, **text_props}, 'selector': {'id': 'default'}}]}}
        return self.add(x, y, w, h, v, container(alt))

    def button(self, x, y, w, h, label, page_id, alt):
        v = {'visualType': 'actionButton', 'objects': {
            'fill': [{'properties': {'show': lit('false')}}],
            'outline': [{'properties': {'show': lit('false')}}],
            'text': [{'properties': {'show': lit('true')}},
                     {'properties': {'text': lit(f"'{label}'"), 'fontColor': color(ACCENT), 'fontSize': lit('16D'),
                                     'fontFamily': lit("'Segoe UI Semibold'"), 'bold': lit('true'),
                                     'horizontalAlignment': lit("'center'"), 'verticalAlignment': lit("'middle'")},
                      'selector': {'id': 'default'}}]}}
        return self.add(x, y, w, h, v, container(alt, background='#FFFFFF', border=ACCENT, radius=8, link=page_id))

    def kpi_card(self, x, y, w, h, measure, label, alt):
        v = {'visualType': 'card',
             'query': {'queryState': {'Values': {'projections': [{
                 'field': {'Measure': {'Expression': {'SourceRef': {'Entity': '_Measures'}}, 'Property': measure}},
                 'queryRef': f'_Measures.{measure}', 'nativeQueryRef': measure}]}}},
             'objects': {'labels': [{'properties': {'color': color('#FFFFFF'), 'fontFamily': lit("'Segoe UI Semibold'"), 'fontSize': lit('33D')}}],
                         'categoryLabels': [{'properties': {'show': lit('true'), 'color': color(LIGHT), 'fontFamily': lit("'Segoe UI'"), 'fontSize': lit('14D')}}]}}
        # the label under the value is the field's display name: rename it for this visual
        v['query']['queryState']['Values']['projections'][0]['displayName'] = label
        return self.add(x, y, w, h, v, container(alt))


def run(size, c, bold=False, family='Segoe UI'):
    s = {'fontFamily': 'Segoe UI Semibold' if bold else family, 'fontSize': f'{size}pt', 'color': c}
    if bold:
        s['fontWeight'] = 'bold'
    return s


# ---- cards of the seven pages: (page id, number, title, tagline, description, answers, button label, accent colour)
CARDS = [
    ('ff862ad3bc453005bb9c', 1, 'Workforce', 'Who works at Acme today', 'Headcount, departments against target, gender, age, tenure and nationality.', 'How big are we and who are we?', 'Open workforce', '#2563EB'),
    ('a0a5139c61208801d6f5', 2, 'Organization', 'How the company is structured', 'Reporting tree, managers and team sizes, and headcount against the workforce plan.', 'Who reports to whom?', 'Open organization', '#0E9F8E'),
    ('48f2971a9ff6cfb17906', 3, 'Career', 'How people move', 'Promotions, transfers and manager changes over time, and the time between promotions.', 'How do careers develop?', 'Open career', '#D9822B'),
    ('3b098c8fe9f9537ea6f6', 4, 'Compensation', 'What people earn', 'Salary by department, level and gender, pay changes over time and total payroll.', 'Is pay fair and consistent?', 'Open compensation', '#7C5CD6'),
    ('32049a889e1837970128', 5, 'Performance', 'How people are rated', 'Annual review ratings by department and manager, rating spread and reviews missing.', 'Where is performance strong?', 'Open performance', '#C8446A'),
    ('b55812a5b5cb18d676b4', 6, 'Leave', 'When people are away', 'Approved leave by type and month, days per employee and who is absent today.', 'How much time off is taken?', 'Open leave', '#2563EB'),
    ('183b9dacf76e4e6435ea', 7, 'Employee profile', 'One person in full', 'Career, salary, reviews and leave for a single employee. Opened by drill-through.', "What is this person's story?", 'Open employee profile', '#0E9F8E'),
]
COL_X = [330, 726, 1122, 1518]
ROW_Y = [216, 645]
CARD_W, CARD_H = 372, 405


def build():
    p = Page()
    wf = os.path.join(PAGES, WORKFORCE, 'visuals')

    # ---- left menu, copied from Workforce: background, title, subtitle, page navigator, footer
    copies = ['1328a6cbb3382e004a07', '9a254d41b94e86c99b9a', 'f1f48f389585e800a337', 'e65dcc70c228282a90dc', '4bcdd01312b960e2860e']
    for vid in copies:
        d = load(os.path.join(wf, vid, 'visual.json'))
        pos = d['position']
        p.add(pos['x'], pos['y'], pos['width'], pos['height'], d['visual'], d['visual'].pop('visualContainerObjects'))

    # ---- header banner
    p.rect(330, 30, 1560, 162, NAVY, 'Header banner')
    p.textbox(354, 48, 1000, 60, [[('Acme Corporation people analytics', run(33, '#FFFFFF', bold=True))]], 'Page title: Acme Corporation people analytics')
    p.textbox(354, 108, 820, 76, [[('Seven pages on headcount, structure, careers, pay, performance and leave. Pick a page to start, or use the menu on the left.', run(16, LIGHT))]],
              'Short description of the report')
    p.kpi_card(1456, 70, 130, 90, 'Headcount', 'employees', 'Employees: total headcount')
    p.kpi_card(1596, 70, 130, 90, 'Departments', 'departments', 'Number of departments')
    p.kpi_card(1738, 70, 140, 90, 'Years of History', 'of history', 'Years of history since the first hire')

    # ---- page cards
    for i, (pid, n, title, tag, desc, answers, button, accent) in enumerate(CARDS):
        x, y = COL_X[i % 4], ROW_Y[i // 4]
        p.rect(x, y, CARD_W, CARD_H, accent, f'{title} card accent')
        p.rect(x, y + 6, CARD_W, CARD_H - 6, '#FFFFFF', f'{title} card', border='#E5E7EB')
        p.shape_text(x + 24, y + 30, 36, 36, 'oval', NAVY,
                     {'fontColor': color('#FFFFFF'), 'fontSize': lit('14D'), 'fontFamily': lit("'Segoe UI Semibold'"), 'bold': lit('true'),
                      'horizontalAlignment': lit("'center'"), 'verticalAlignment': lit("'middle'")},
                     f'Page number {n}', lit(f"'{n}'"))
        p.textbox(x + 72, y + 24, 280, 48, [[(title, run(20, TEXT, bold=True))]], f'{title} title')
        p.textbox(x + 12, y + 80, 348, 180, [[(tag, run(16, TEXT, bold=True))], [(desc, run(14, MUTED))]], f'{title}: what the page shows')
        p.textbox(x + 12, y + 270, 348, 56, [[('Answers: ', run(14, MUTED)), (answers, run(14, TEXT, bold=True))]], f'{title}: question the page answers')
        p.button(x + 16, y + 336, 340, 52, f'{button} →', pid, f'{button}: go to the {title} page')

    # ---- "Using the report" card
    x, y = COL_X[3], ROW_Y[1]
    p.rect(x, y, CARD_W, CARD_H, '#EEF2FF', 'Using the report card', border='#D6DDF5')
    p.textbox(x + 16, y + 24, 340, 270,
              [[('Using the report', run(16, TEXT, bold=True))],
               [('•  Slicers at the top of each page filter that page.', run(14, TEXT))],
               [('•  Click a chart value to filter the other charts.', run(14, TEXT))],
               [('•  Click an employee name to open the profile page.', run(14, TEXT))],
               [('•  Use Home to come back here.', run(14, TEXT))]], 'How to use the report')
    p.shape_text(x + 16, y + 310, 340, 80, 'rectangle',
                 None, {'fontColor': color(MUTED), 'fontSize': lit('14D'), 'fontFamily': lit("'Segoe UI'"),
                        'horizontalAlignment': lit("'left'"), 'verticalAlignment': lit("'bottom'")},
                 'Data note', {'expr': {'Measure': {'Expression': {'SourceRef': {'Entity': '_Measures'}}, 'Property': 'Text: Home Data Note'}}})
    return p


def write_page(p):
    page_dir = os.path.join(PAGES, HOME)
    if os.path.isdir(page_dir):
        shutil.rmtree(page_dir)
    wf_page = load(os.path.join(PAGES, WORKFORCE, 'page.json'))
    page = {'$schema': wf_page['$schema'], 'name': HOME, 'displayName': 'Home', 'displayOption': 'FitToPage',
            'height': 1080, 'width': 1920, 'objects': copy.deepcopy(wf_page['objects'])}
    dump(os.path.join(page_dir, 'page.json'), page)

    # info pop-up (button, hidden panel, hidden close button) copied from Workforce, with new bookmarks
    wf = os.path.join(PAGES, WORKFORCE, 'visuals')
    on, off = secrets.token_hex(10), secrets.token_hex(10)
    info = {}
    for key, vid in (('btn', '73026b41b1e28b126005'), ('panel', '0a3de5946b3269d59005'), ('close', '76ad526d79c332bc0433')):
        d = load(os.path.join(wf, vid, 'visual.json'))
        info[key] = d
    names = {k: secrets.token_hex(10) for k in info}
    z = (len(p.visuals) + 1) * 1000
    for i, (key, bookmark) in enumerate((('btn', on), ('panel', None), ('close', off))):
        d = info[key]
        d['name'] = names[key]
        d['position'].update(z=z + i * 1000, tabOrder=z + i * 1000)
        if bookmark:
            d['visual']['visualContainerObjects']['visualLink'][0]['properties']['bookmark'] = lit(f"'{bookmark}'")
        dump(os.path.join(page_dir, 'visuals', names[key], 'visual.json'), d)

    for i, (name, v) in enumerate(p.visuals):
        z_ = (i + 1) * 1000
        doc = {'$schema': SCHEMA, 'name': name,
               'position': {'x': v['x'], 'y': v['y'], 'z': z_, 'height': v['h'], 'width': v['w'], 'tabOrder': z_},
               'visual': {**v['visual'], 'visualContainerObjects': v['container'], 'drillFilterOtherVisuals': True}}
        dump(os.path.join(page_dir, 'visuals', name, 'visual.json'), doc)

    # bookmarks Info ON / Info OFF (only the three info visuals change)
    bm = load(os.path.join(DEF, 'bookmarks', 'bookmarks.json'))
    old = [b for b in glob.glob(os.path.join(DEF, 'bookmarks', '*.bookmark.json')) if load(b)['explorationState']['activeSection'] == HOME]
    for f in old:
        os.remove(f)
        bm['items'] = [i for i in bm['items'] if i['name'] != os.path.basename(f).split('.')[0]]
    for bname, label, show in ((on, 'Home Info ON', True), (off, 'Home Info OFF', False)):
        def vis(t, hidden):
            s = {'visualType': t, 'objects': {}}
            if hidden:
                s['display'] = {'mode': 'hidden'}
            return {'singleVisual': s}
        vc = {names['btn']: vis('actionButton', show), names['panel']: vis('shape', not show), names['close']: vis('actionButton', not show)}
        dump(os.path.join(DEF, 'bookmarks', f'{bname}.bookmark.json'), {
            '$schema': 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.1.0/schema.json',
            'displayName': label, 'name': bname,
            'options': {'targetVisualNames': list(names.values()), 'suppressData': True},
            'explorationState': {'version': '1.3', 'activeSection': HOME, 'sections': {HOME: {'visualContainers': vc}}}})
        bm['items'].append({'name': bname})
    dump(os.path.join(DEF, 'bookmarks', 'bookmarks.json'), bm)

    # Home is the first page and the page the report opens on
    meta = load(os.path.join(PAGES, 'pages.json'))
    meta['pageOrder'] = [HOME] + [i for i in meta['pageOrder'] if i != HOME]
    meta['activePageName'] = HOME
    dump(os.path.join(PAGES, 'pages.json'), meta)


if __name__ == '__main__':
    page = build()
    write_page(page)
    print('Home page written with', len(page.visuals) + 3, 'visuals')
