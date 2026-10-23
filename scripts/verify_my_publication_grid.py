"""Exercise the owner-only post grid and delete flow with disposable synthetic data."""
import io
import json
import urllib.error
import urllib.request
from pathlib import Path
from uuid import uuid4

from PIL import Image

root = Path(__file__).resolve().parent.parent
public = json.loads((root / '.local/supabase-public.json').read_text())
assert public['url'] == 'https://pmrvzpuznwzuejbuhaqm.supabase.co'
identity = next(i for i in json.loads((root / '.local/supabase-test-identities.json').read_text()) if i['role'] == 'owner')
pet = json.loads((root / '.local/supabase-test-sessions.json').read_text())['pet_id']
checks = []


def call(path, body=None, token=None, raw=None):
    headers = {'apikey': public['anon_key']}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if body is not None:
        raw = json.dumps(body).encode()
        headers['Content-Type'] = 'application/json'
    elif raw is not None:
        headers['Content-Type'] = 'image/jpeg'
    request = urllib.request.Request(public['url'] + path, data=raw, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=40) as response:
            data = response.read()
            return response.status, json.loads(data) if 'json' in response.headers.get('Content-Type', '') else data
    except urllib.error.HTTPError as error:
        return error.code, {}


def check(name, result, expected=200, predicate=lambda _: True):
    status, data = result
    passed = (status in expected if isinstance(expected, tuple) else status == expected) and predicate(data)
    checks.append({'check': name, 'passed': passed, 'status': status})
    if not passed:
        raise AssertionError(name)
    return data


def rpc(name, body=None, token=None):
    return call('/rest/v1/rpc/mefrion_' + name, body or {}, token)


owner = None
photo = None
post = None
outcome = None
try:
    auth = check('synthetic-owner-login', call('/auth/v1/token?grant_type=password',
                                                   {'email': identity['email'], 'password': identity['password']}))
    owner = auth['access_token']
    check('anonymous-list-rejected', rpc('my_publications', {'p_limit': 5}), 401)
    photo = check('reserve-synthetic-original', rpc('begin_photo',
                  {'p_pet': pet, 'p_request_key': str(uuid4()), 'p_title': 'grid test'}, owner))
    image = Image.new('RGB', (320, 320), (230, 145, 158))
    output = io.BytesIO()
    image.save(output, format='JPEG')
    check('upload-synthetic-original', call('/storage/v1/object/family-originals/' + photo['path'],
          token=owner, raw=output.getvalue()), (200, 201))
    check('finish-synthetic-original', rpc('finish_photo', {'p_photo': photo['id']}, owner))
    check('explicit-public-profile', rpc('set_public_profile',
          {'p_pet': pet, 'p_enabled': True, 'p_explicit': True}, owner))
    check('explicit-photo-consent', rpc('consent',
          {'p_photo': photo['id'], 'p_purpose': 'sns', 'p_allowed': True}, owner))
    post = check('request-pending-post', rpc('request_tagged_publication',
                 {'p_pet': pet, 'p_photos': [photo['id']], 'p_tags': [pet], 'p_body': 'synthetic grid test',
                  'p_request_key': str(uuid4()), 'p_explicit': True}, owner))['id']
    records = check('owner-list-has-pending-thumbnail', rpc('my_publications', {'p_limit': 50}, owner),
                    predicate=lambda rows: any(row['id'] == post and row['preview_photo'] == photo['id']
                                               and row['media'] == [] for row in rows))
    check('private-preview-owner-access', call('/functions/v1/private-image?photo=' + photo['id'], token=owner),
          predicate=lambda body: isinstance(body, bytes) and body.startswith(b'\xff\xd8'))
    check('owner-can-remove-post', rpc('stop_publication', {'p_post': post}, owner))
    check('removed-post-absent-from-grid', rpc('my_publications', {'p_limit': 50}, owner),
          predicate=lambda rows: all(row['id'] != post for row in rows))
    check('family-original-preserved', call('/functions/v1/private-image?photo=' + photo['id'], token=owner),
          predicate=lambda body: isinstance(body, bytes) and body.startswith(b'\xff\xd8'))
    outcome = {'passed': True, 'checks': checks}
except Exception as error:
    outcome = {'passed': False, 'failure': str(error), 'checks': checks}
finally:
    if owner:
        if post:
            rpc('stop_publication', {'p_post': post}, owner)
        rpc('set_public_profile', {'p_pet': pet, 'p_enabled': False}, owner)
        if photo:
            rpc('delete_photo', {'p_photo': photo['id']}, owner)
    evidence = root / 'docs/evidence/my-publication-grid-e2e.json'
    evidence.write_text(json.dumps(outcome, ensure_ascii=False, indent=2))
    print(json.dumps({'passed': outcome['passed'], 'checks': len(checks), 'failure': outcome.get('failure')}))
if not outcome['passed']:
    raise SystemExit(1)
