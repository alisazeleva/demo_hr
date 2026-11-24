"""Usage: python tools/validate_pbir.py [report definition folder]   (needs: pip install jsonschema referencing)
Validate PBIR files against the official Microsoft JSON schemas (downloaded on demand, cached in memory)."""
import sys, json, glob, os, re, urllib.request, urllib.error
from jsonschema import Draft7Validator, Draft202012Validator, validators
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT7, DRAFT202012

cache = {}
fallback = set()   # schema URIs that were replaced by a lower version
# Properties that newer schema versions added; allowed only when an older schema is used in their place.
NEWER_PROPERTIES = {'linguisticSchemaSyncVersion'}   # report.json, report schema 3.4.0
def fetch(uri):
    # Desktop sometimes writes a schema version that Microsoft has not published yet (for example
    # visualContainer 2.15.0 or report 3.4.0). Then fall back to the nearest lower minor version that exists.
    if uri not in cache:
        m = re.search(r'/(\d+)\.(\d+)\.(\d+)/', uri)
        candidates = [uri]
        if m:
            major, minor = int(m.group(1)), int(m.group(2))
            candidates += [uri.replace(m.group(0), f'/{major}.{n}.0/') for n in range(minor - 1, -1, -1)]
        for alt in candidates:
            try:
                with urllib.request.urlopen(alt, timeout=60) as r:
                    cache[uri] = json.loads(r.read().decode('utf-8'))
                if alt != uri:
                    fallback.add(uri)
                break
            except urllib.error.HTTPError as e:
                if e.code != 404 or alt == candidates[-1]:
                    raise
    return cache[uri]
def doc_at(doc, path):
    for p in path:
        doc = doc[p]
    return doc
def retrieve(uri):
    doc = fetch(uri)
    spec = DRAFT202012 if '2020-12' in doc.get('$schema', '') else DRAFT7
    return Resource.from_contents(doc, default_specification=spec)
registry = Registry(retrieve=retrieve)

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'Acme HR Demo.Report', 'definition')
files = glob.glob(os.path.join(root, '**', '*.json'), recursive=True)
total = bad = 0
for f in sorted(files):
    rel = os.path.relpath(f, root)
    if 'StaticResources' in f: continue
    try:
        doc = json.load(open(f, encoding='utf-8'))
    except Exception as e:
        print('INVALID JSON', rel, e); bad += 1; continue
    uri = doc.get('$schema')
    if not uri: continue
    sch = fetch(uri)
    cls = validators.validator_for(sch, default=Draft7Validator)
    v = cls(sch, registry=registry)
    errs = [e for e in sorted(v.iter_errors(doc), key=lambda e: list(e.absolute_path)) if list(e.absolute_path) != ['$schema']]
    if uri in fallback:
        errs = [e for e in errs if not (e.validator == 'additionalProperties'
                                        and set(doc_at(doc, e.absolute_path)) - set(e.schema.get('properties', {}))
                                        <= NEWER_PROPERTIES)]
    total += 1
    if errs:
        bad += 1
        print(f'--- {rel}: {len(errs)} problem(s)')
        for e in errs[:8]:
            path = '/'.join(str(p) for p in e.absolute_path)
            print('   ', path or '(root)', '->', e.message[:230])
print(f'\nchecked {total} files, {bad} with problems')
