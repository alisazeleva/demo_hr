"""Repository checks for the Power BI project (no Desktop needed).

Run from the repo root:  python -m pytest tests -q
Needs: pip install -r tests/requirements.txt
"""
import glob
import json
import os
import re
import subprocess
import sys

import pytest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL = os.path.join(REPO, 'hr_dashboard.SemanticModel', 'definition')
REPORT = os.path.join(REPO, 'hr_dashboard.Report', 'definition')


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def load(path):
    return json.loads(read(path))


# ---------------------------------------------------------------- model parsing
def parse_model():
    """Return (columns, measures): columns {table: set(names)}, measures {name: dict}."""
    columns, measures = {}, {}
    for f in glob.glob(os.path.join(MODEL, 'tables', '*.tmdl')):
        text = read(f)
        table = re.search(r"^table ('?)(.+?)\1\s*$", text, re.M).group(2)
        columns[table] = set()
        # a block starts at a tab-indented "column" or "measure" line; a "///" line just before it is its description
        for m in re.finditer(r"((?:\t///[^\n]*\n)*)\t(column|measure) ('[^']+'|[^\s=]+)([^\n]*)\n((?:\t\t[^\n]*\n|\n(?=\t\t))*)", text):
            desc, kind, name, rest, body = m.groups()
            name = name.strip("'")
            if kind == 'column':
                columns[table].add(name)
            else:
                measures[name] = dict(
                    table=table, description=desc.strip(), body=rest + '\n' + body,
                    folder=re.search(r"^\t\tdisplayFolder: (.+)$", body, re.M),
                    multiline=rest.rstrip().endswith('='))
    return columns, measures


COLUMNS, MEASURES = parse_model()
REPORT_FILES = [f for f in glob.glob(os.path.join(REPORT, '**', '*.json'), recursive=True) if 'StaticResources' not in f]
REPORT_TEXT = {f: read(f) for f in REPORT_FILES}


def rel(path):
    return os.path.relpath(path, REPO).replace('\\', '/')


# ---------------------------------------------------------------- schema
def test_pbir_files_match_microsoft_schemas():
    pytest.importorskip('jsonschema')
    pytest.importorskip('referencing')
    r = subprocess.run([sys.executable, os.path.join(REPO, 'tools', 'validate_pbir.py')], capture_output=True, text=True)
    assert r.returncode == 0 and ' 0 with problems' in r.stdout, r.stdout[-3000:] + r.stderr[-1000:]


# ---------------------------------------------------------------- measures
def test_model_was_parsed():
    assert len(MEASURES) >= 60 and 'Headcount' in MEASURES and 'DimEmployee' in COLUMNS


def test_every_measure_has_description_and_folder():
    bad = [n for n, m in MEASURES.items() if not m['description'] or not m['folder']]
    assert not bad, f'measures without description or display folder: {bad}'


def test_every_measure_is_in_the_measures_table():
    bad = [n for n, m in MEASURES.items() if m['table'] != '_Measures']
    assert not bad, f'measures outside _Measures: {bad}'


def formula_lines(m):
    """Lines of the DAX formula (before the first property such as formatString or displayFolder)."""
    lines = m['body'].split('\n')[1:]
    return [l for l in lines if l.startswith('\t\t\t')]


def test_non_trivial_measures_have_comments():
    """CLAUDE.md: a // comment for every non-trivial measure; here, a formula of more than 6 lines."""
    bad = [n for n, m in MEASURES.items() if len(formula_lines(m)) > 6 and '//' not in m['body']]
    assert not bad, f'measures with a long formula and no // comment: {bad}'


def test_text_measures_are_filed_in_text_or_profile_folder():
    bad = [n for n, m in MEASURES.items()
           if n.startswith('Text: ') and not (m['folder'] and m['folder'].group(1).strip() in ('Text', 'Profile'))]
    assert not bad, f'"Text: " measures must be in the Text or Profile folder: {bad}'


def test_measures_are_used():
    """A measure must be used by another measure, a visual, a filter or conditional formatting."""
    all_dax = '\n'.join(m['body'] for m in MEASURES.values())
    unused = []
    for name in MEASURES:
        in_dax = sum(f'[{name}]' in m['body'] and n != name for n, m in MEASURES.items()) > 0
        in_report = any(re.search(r'"(?:[^"]*\.)?%s"' % re.escape(name), t) for t in REPORT_TEXT.values())
        if not (in_dax or in_report):
            unused.append(name)
    assert not unused, f'unused measures: {unused}'


# ---------------------------------------------------------------- report fields exist in the model
def collect_refs(node, aliases, out):
    if isinstance(node, dict):
        if isinstance(node.get('From'), list):
            aliases = dict(aliases)
            for fr in node['From']:
                if isinstance(fr, dict) and 'Name' in fr and 'Entity' in fr:
                    aliases[fr['Name']] = fr['Entity']
        for kind in ('Column', 'Measure'):
            c = node.get(kind)
            if isinstance(c, dict) and 'Property' in c and isinstance(c.get('Expression'), dict):
                sr = c['Expression'].get('SourceRef')
                if sr:
                    out.append((kind, sr.get('Entity') or aliases.get(sr.get('Source')), c['Property']))
        for v in node.values():
            collect_refs(v, aliases, out)
    elif isinstance(node, list):
        for v in node:
            collect_refs(v, aliases, out)


def test_fields_used_by_visuals_exist_in_the_model():
    missing = set()
    for f in REPORT_FILES:
        try:
            doc = json.loads(REPORT_TEXT[f])
        except ValueError:
            continue
        refs = []
        collect_refs(doc, {}, refs)
        for kind, entity, prop in refs:
            if entity is None:
                continue
            ok = prop in MEASURES and MEASURES[prop]['table'] == entity if kind == 'Measure' else prop in COLUMNS.get(entity, ())
            if not ok:
                missing.add(f'{kind} {entity}[{prop}] in {rel(f)}')
    assert not missing, '\n'.join(sorted(missing))


def test_dax_only_references_columns_that_exist():
    """Table[Column] references inside measures and calculated columns must exist."""
    missing = set()
    texts = [m['body'] for m in MEASURES.values()]
    for f in glob.glob(os.path.join(MODEL, 'tables', '*.tmdl')):
        texts.append(read(f))
    for text in texts:
        text = re.sub(r'"[^"\n]*"', '""', text)  # ignore string literals
        for m in re.finditer(r"(?:'([^']+)'|\b([A-Za-z_][A-Za-z0-9_]*))\[([^\]]+)\]", text):
            table, col = m.group(1) or m.group(2), m.group(3)
            if table in COLUMNS and col not in COLUMNS[table] and col not in MEASURES:
                missing.add(f'{table}[{col}]')
    assert not missing, sorted(missing)


# ---------------------------------------------------------------- pages, bookmarks, buttons
PAGES = {}
for p in glob.glob(os.path.join(REPORT, 'pages', '*', 'page.json')):
    pid = os.path.basename(os.path.dirname(p))
    visuals = {os.path.basename(os.path.dirname(v)): load(v)
               for v in glob.glob(os.path.join(os.path.dirname(p), 'visuals', '*', 'visual.json'))}
    PAGES[pid] = dict(page=load(p), visuals=visuals)
BOOKMARKS = {os.path.basename(f).split('.')[0]: load(f) for f in glob.glob(os.path.join(REPORT, 'bookmarks', '*.bookmark.json'))}


def test_page_and_visual_names_match_their_folders():
    bad = [pid for pid, p in PAGES.items() if p['page']['name'] != pid]
    bad += [f'{pid}/{vid}' for pid, p in PAGES.items() for vid, v in p['visuals'].items() if v['name'] != vid]
    assert not bad, bad


def test_page_order_lists_every_page_once():
    meta = load(os.path.join(REPORT, 'pages', 'pages.json'))
    assert sorted(meta['pageOrder']) == sorted(PAGES)
    assert meta['activePageName'] in PAGES


def test_bookmark_list_matches_bookmark_files():
    listed = [i['name'] for i in load(os.path.join(REPORT, 'bookmarks', 'bookmarks.json'))['items']]
    assert len(listed) == len(set(listed)), 'duplicate bookmark in bookmarks.json'
    assert sorted(listed) == sorted(BOOKMARKS)
    assert all(b['name'] == n for n, b in BOOKMARKS.items())


def test_bookmarks_point_to_existing_pages_and_visuals():
    bad = []
    for name, b in BOOKMARKS.items():
        state = b['explorationState']
        if state['activeSection'] not in PAGES:
            bad.append(f'{b["displayName"]}: page {state["activeSection"]} missing')
            continue
        for sec, sv in state['sections'].items():
            visuals = PAGES.get(sec, {}).get('visuals', {})
            for vid in list(sv.get('visualContainers', {})) + b['options'].get('targetVisualNames', []):
                if vid not in visuals:
                    bad.append(f'{b["displayName"]}: visual {vid} missing on page {sec}')
    assert not bad, bad


def test_button_links_point_to_existing_bookmarks_and_pages():
    bad = []
    page_names = set(PAGES)
    for pid, p in PAGES.items():
        for vid, v in p['visuals'].items():
            link = v['visual'].get('visualContainerObjects', {}).get('visualLink')
            if not link:
                continue
            props = link[0]['properties']
            lit = lambda k: props[k]['expr']['Literal']['Value'].strip("'") if k in props else None
            if lit('type') == 'Bookmark' and lit('bookmark') not in BOOKMARKS:
                bad.append(f'{pid}/{vid}: bookmark {lit("bookmark")} missing')
            if lit('type') == 'PageNavigation' and lit('navigationSection') not in page_names:
                bad.append(f'{pid}/{vid}: page {lit("navigationSection")} missing')
    assert not bad, bad


def test_every_page_has_info_on_off_bookmarks_and_a_working_info_button():
    """Each page has an Info ON and Info OFF bookmark; the ON bookmark opens the panel, the OFF one closes it."""
    bad = []
    for pid, p in PAGES.items():
        on = [b for b in BOOKMARKS.values() if b['explorationState']['activeSection'] == pid and b['displayName'].endswith('Info ON')]
        off = [b for b in BOOKMARKS.values() if b['explorationState']['activeSection'] == pid and b['displayName'].endswith('Info OFF')]
        if len(on) != 1 or len(off) != 1:
            bad.append(f'{p["page"]["displayName"]}: needs exactly one Info ON and one Info OFF bookmark')
            continue
        panels = [vid for vid, v in p['visuals'].items()
                  if 'Text: Info Note' in json.dumps(v)]
        if len(panels) != 1:
            bad.append(f'{p["page"]["displayName"]}: needs exactly one panel showing Text: Info Note')
            continue
        panel = panels[0]
        if not p['visuals'][panel].get('isHidden'):
            bad.append(f'{p["page"]["displayName"]}: the info panel must be hidden by default')
        if on[0]['explorationState']['sections'][pid]['visualContainers'].get(panel, {}).get('singleVisual', {}).get('display'):
            bad.append(f'{p["page"]["displayName"]}: Info ON must show the panel')
        if not off[0]['explorationState']['sections'][pid]['visualContainers'].get(panel, {}).get('singleVisual', {}).get('display'):
            bad.append(f'{p["page"]["displayName"]}: Info OFF must hide the panel')
        targets = [vid for vid, v in p['visuals'].items()
                   if v['visual'].get('visualContainerObjects', {}).get('visualLink', [{}])[0].get('properties', {}).get('bookmark', {}).get('expr', {}).get('Literal', {}).get('Value', '').strip("'") == on[0]['name']]
        if len(targets) != 1:
            bad.append(f'{p["page"]["displayName"]}: exactly one button must open the Info ON bookmark (found {len(targets)})')
    assert not bad, bad


# ---------------------------------------------------------------- privacy (the repo is public)
def tracked_text_files():
    r = subprocess.run(['git', 'ls-files'], cwd=REPO, capture_output=True, text=True)
    if r.returncode != 0:
        pytest.skip('not a git repository')
    exts = ('.md', '.json', '.tmdl', '.py', '.dax', '.pbip', '.pbir', '.txt', '.sql', '.m')
    return [os.path.join(REPO, f) for f in r.stdout.splitlines() if f.lower().endswith(exts)]


def test_no_personal_paths_emails_or_secrets_in_tracked_files():
    patterns = {
        'local user path': re.compile(r'[A-Za-z]:[\\/]+Users[\\/]', re.I),
        'email address': re.compile(r'[\w.+-]+@(?!acmecorp\.example)[\w-]+\.[\w.]+'),
        'password or key': re.compile(r'(password|pwd|secret|api[_-]?key)\s*[=:]\s*\S+', re.I),
    }
    hits = []
    for f in tracked_text_files():
        if os.path.basename(f) == 'test_repo.py':
            continue
        try:
            text = read(f)
        except (UnicodeDecodeError, OSError):
            continue
        for label, rx in patterns.items():
            m = rx.search(text)
            if m:
                hits.append(f'{rel(f)}: {label}: {m.group(0)[:60]}')
    assert not hits, '\n'.join(hits)


# ---------------------------------------------------------------- DAX test file
def test_measures_in_dax_tests_exist():
    """tests/measures.dax is run by hand against the open model; this catches renamed or removed measures."""
    text = re.sub(r'"[^"\n]*"', '""', read(os.path.join(REPO, 'tests', 'measures.dax')))
    text = re.sub(r'//[^\n]*', '', text)
    used = {m for m in re.findall(r'(?<![A-Za-z0-9_\'\]])\[([^\]]+)\]', text)}
    missing = sorted(n for n in used if n not in MEASURES and n not in {c for cols in COLUMNS.values() for c in cols}
                     and n not in ('Test', 'Actual', 'Expected', 'Result'))
    assert not missing, f'measures.dax uses unknown measures: {missing}'
