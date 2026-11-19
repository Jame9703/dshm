#!/usr/bin/env python3
"""Recover interrupted temporary edits only when bytes match pre-build digest."""
import hashlib
import json
import pathlib
import subprocess
import itertools

R = pathlib.Path(__file__).resolve().parent.parent
expected = json.loads((R/'dist/acceptance/fix-review-dual-release/phase5-original.json').read_text())
def h(b): return hashlib.sha256(b).hexdigest()
for name, digest in expected.items():
    p = R/name
    data = p.read_bytes()
    if h(data) == digest: continue
    if name == 'build-profile.json5': continue
    candidate = data.replace(b'com.dshm.dshmbeta', b'com.dshm.dshclient')
    if name.endswith('/element/string.json'):
        candidate = candidate.replace(b'"value": "DSHM beta"', b'"value": "DSHM"')
        candidate = candidate.replace(b'"value": "Jinghong beta"', b'"value": "Jinghong"')
    if h(candidate) != digest:
        pieces = data.split(b'com.dshm.dshmbeta')
        if len(pieces) < 16:
            for choices in itertools.product([b'com.dshm.dshmbeta', b'com.dshm.dshclient'], repeat=len(pieces)-1):
                trial = pieces[0]
                for choice, piece in zip(choices, pieces[1:]): trial += choice + piece
                if h(trial) == digest:
                    candidate = trial
                    break
    if h(candidate) != digest:
        tracked = subprocess.run(['git','show','HEAD:'+name], cwd=R, capture_output=True)
        if tracked.returncode == 0 and h(tracked.stdout) == digest:
            candidate = tracked.stdout
    assert h(candidate) == digest, 'not exact recovery: '+name
    p.write_bytes(candidate)
    print('Exact byte recovery:', name)
p = R/'build-profile.json5'
current = json.loads(p.read_text())
print('Temporary profile structure (no credentials):', json.dumps({
    'products': [{k:v for k,v in x.items() if k != 'material'} for x in current['app']['products']],
    'modules': current['modules'],
    'topKeys': list(current), 'appKeys': list(current['app'])}, ensure_ascii=False))
for root in [R/'.hvigor', R/'.workbuddy', R/'.deveco', R/'AGC-operations']:
    if not root.exists(): continue
    for f in root.rglob('*'):
        if f.is_file() and f.stat().st_size < 200000:
            try: data = f.read_bytes()
            except OSError: continue
            if h(data) == expected['build-profile.json5']:
                p.write_bytes(data)
                print('Exact original profile recovered from', f)
                break
print('PROFILE_EXACT=', h(p.read_bytes()) == expected['build-profile.json5'])
if h(p.read_bytes()) != expected['build-profile.json5']:
    source = p.read_text().replace('com.dshm.dshmbeta', 'com.dshm.dshclient').replace(
        './signing/debug/default_desktop.ohos.arm64_H6ERYybQIgIZaVstkvwvtC9vr-nLxAUfZBhCBJKkRhw=.p7b',
        './.certs/multihap-20261024/DSHM-multihap-debug-pc-phone-20261024.p7b')
    for bundle in ['com.dshm.dshclient', None]:
        obj = json.loads(source)
        if bundle is None: obj['app']['products'][0].pop('bundleName', None)
        for indent in [2, 4]:
            for newline in ['\n', '\r\n']:
                for trailing in ['', '\n']:
                    trial = (json.dumps(obj, indent=indent, ensure_ascii=False)+trailing).replace('\n', newline).encode()
                    if h(trial) == expected['build-profile.json5']:
                        p.write_bytes(trial)
                        print('PROFILE_EXACT_RECOVERED=True')
if h(p.read_bytes()) != expected['build-profile.json5']:
    import copy
    obj = json.loads(p.read_text())
    for profile_old, bundle, sign, phone_products in itertools.product([False, True], [None,'com.dshm.dshclient'], ['debug','default','release'], [None,['default'],['phone']]):
        base = copy.deepcopy(obj)
        product = base['app']['products'][0]
        product['signingConfig'] = sign
        if bundle is None: product.pop('bundleName',None)
        else: product['bundleName'] = bundle
        for item in base['app']['signingConfigs']:
            if profile_old and item['name'] == 'debug':
                item['material']['profile'] = './.certs/multihap-20261024/DSHM-multihap-debug-pc-phone-20261024.p7b'
        for mod in base['modules']:
            if mod['name'] == 'phone':
                if phone_products is None: mod['targets'][0].pop('applyToProducts',None)
                else: mod['targets'][0]['applyToProducts'] = phone_products
        for indent, trailing, newline in itertools.product([2,4], ['', '\n'], ['\n','\r\n']):
            trial = (json.dumps(base,indent=indent,ensure_ascii=False)+trailing).replace('\n',newline).encode()
            if h(trial) == expected['build-profile.json5']:
                p.write_bytes(trial)
                print('PROFILE_EXACT_RECOVERED=True')
if h(p.read_bytes()) != expected['build-profile.json5']:
    import os
    for directory, dirs, files in os.walk(pathlib.Path.home()):
        dirs[:] = [d for d in dirs if d not in ['node_modules','.git','Download','harmonyos-docs','HarmonyOS-KB']]
        found = False
        for name in files:
            f = pathlib.Path(directory)/name
            try:
                if f.stat().st_size != 3425: continue
                data = f.read_bytes()
            except OSError: continue
            if h(data) == expected['build-profile.json5']:
                p.write_bytes(data)
                print('Original exact bytes recovered from local history:',f)
                found = True
                break
        if found: break
assert h(p.read_bytes()) == expected['build-profile.json5'], 'profile original not recovered'
