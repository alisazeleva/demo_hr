"""Usage: python tools/validate_pbir.py [report definition folder]   (needs: pip install jsonschema referencing)
Validate PBIR files against the official Microsoft JSON schemas (downloaded on demand, cached in memory)."""
import sys, json, glob, os, urllib.request
from jsonschema import Draft7Validator, Draft202012Validator, validators
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT7, DRAFT202012

cache = {}
def fetch(uri):
    if uri not in cache:
        try:
            with urllib.request.urlopen(uri, timeout=60) as r:
                cache[uri] = json.loads(r.read().decode('utf-8'))
        except Exception:
            alt = uri.replace('/2.14.0/', '/2.13.0/')
            with urllib.request.urlopen(alt, timeout=60) as r:
                cache[uri] = json.loads(r.read().decode('utf-8'))
    return cache[uri]
def retrieve(uri):
    doc = fetch(uri)
    spec = DRAFT202012 if '2020-12' in doc.get('$schema', '') else DRAFT7
    return Resource.from_contents(doc, default_specification=spec)
registry = Registry(retrieve=retrieve)

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'hr_dashboard.Report', 'definition')
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
    total += 1
    if errs:
        bad += 1
        print(f'--- {rel}: {len(errs)} problem(s)')
        for e in errs[:8]:
            path = '/'.join(str(p) for p in e.absolute_path)
            print('   ', path or '(root)', '->', e.message[:230])
print(f'\nchecked {total} files, {bad} with problems')
