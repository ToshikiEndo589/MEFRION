"""Publish exactly 20 Pexels-backed managed posts in the approved Free dev project.

Uses the existing test-only technical publisher and a temporary MFA test operator.
It never accepts a production URL, and withdraws this run's Pets on failure.
"""
import csv
import hashlib
import json
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import UUID, uuid4

from p1_test_support import ROOT, DevelopmentClient
from stock_pet_names import DOG_NAMES, CAT_NAMES
from prepare_stock_seed_50_breeds import EXPLICIT

STATE = ROOT / '.local/stock-seed-test-20.json'
ROWS = ROOT / 'release/stock-seed-plan/queue.csv'


def main():
    subprocess.run([sys.executable, '-c', 'import PIL'], check=True, capture_output=True,
                   timeout=10)  # Public derivative worker needs Pillow; fail before mutations.
    if STATE.exists():
        prior = json.loads(STATE.read_text())
        raise RuntimeError(f"Existing stock test state is {prior.get('status')}; refuse a duplicate run")
    rows = list(csv.DictReader(ROWS.open(newline='')))[:20]
    assert len(rows) == 20 and len({r['asset_id'] for r in rows}) == 20
    assert all(r['rights_state'] == 'pending_individual_review' for r in rows)
    assert {r['species'] for r in rows} == {'dog', 'cat'}
    public = json.loads((ROOT / '.local/supabase-public.json').read_text())
    service = json.loads((ROOT / '.local/supabase-server.json').read_text())
    assert public['url'] == service['url'] == 'https://pmrvzpuznwzuejbuhaqm.supabase.co'
    publisher = json.loads((ROOT / '.local/seed-publisher-test.json').read_text())['id']
    client = DevelopmentClient()
    state = {'status': 'starting', 'scope': 'Free development only', 'requested': 20,
             'publisher': publisher, 'pets': [], 'photos': [], 'jobs': [],
             'asset_ids': [r['asset_id'] for r in rows]}

    def save():
        STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2) + '\n')
        STATE.chmod(0o600)

    def rpc(name, body, role='operator'):
        status, value = client.rpc(name, body, role)
        if status != 200:
            raise RuntimeError(f'{name} failed ({status})')
        return value

    def privileged(name, body):
        import urllib.request
        headers = {'apikey': service['secret_key'], 'Authorization': 'Bearer ' + service['secret_key'],
                   'Content-Type': 'application/json'}
        request = urllib.request.Request(service['url'] + '/rest/v1/rpc/mefrion_' + name,
                                         data=json.dumps(body).encode(), headers=headers)
        with urllib.request.urlopen(request, timeout=40) as response:
            return json.load(response)

    save()
    operator_ready = False
    try:
        subprocess.run([sys.executable, str(ROOT / 'scripts/stage_operator_ui_fixture.py')],
                       check=True, capture_output=True, text=True, timeout=90)
        operator_ready = True
        fixture = json.loads((ROOT / '.local/operator-browser-fixture.json').read_text())
        assert fixture['email'].startswith('mefrion-test-') and fixture['email'].endswith('@example.invalid')
        client.tokens['operator'] = fixture['access_token']
        assert privileged('register_test_publisher', {'p_publisher': publisher}) is True
        assert privileged('grant_test_operator', {'p_user': fixture['id'], 'p_role': 'admin', 'p_active': True}) is True
        existing = rpc('seed_list', {})
        if any(job['state'] in ('scheduled', 'dispatching') for pet in existing['pets'] for job in pet['jobs']):
            raise RuntimeError('Other managed jobs are due; refuse a shared dispatcher run')

        indexes = {'dog': 0, 'cat': 0}
        profiles = []
        for row in rows:
            species = row['species']
            names = DOG_NAMES if species == 'dog' else CAT_NAMES
            name = names[indexes[species]]
            indexes[species] += 1
            asset = row['asset_id'].split('-', 1)[1]
            breed = ''
            if asset in EXPLICIT:
                phrase, label = EXPLICIT[asset]
                record = json.loads((ROOT / '.local/pexels-pets/records' / (asset + '.json')).read_text())
                if phrase.casefold() not in record['alt'].casefold():
                    raise RuntimeError('Unverified breed: ' + asset)
                breed = label.replace('（推定）', '')
            profiles.append({'key': 'stock-test-' + asset + '-' + uuid4().hex[:8],
                             'name': name, 'species': species, 'breed': breed,
                             'source': 'Pexels reference photo: ' + row['source_page'],
                             'introduction': ''})
        made = rpc('seed_create', {'p_publisher': publisher, 'p_items': profiles, 'p_key': str(uuid4())})
        if len(made) != len(rows):
            raise RuntimeError('Managed Pet batch returned an unexpected count')
        pet_by_asset = {row['asset_id']: pet['id'] for row, pet in zip(rows, made)}
        state['pets'] = list(pet_by_asset.values())
        state['status'] = 'staging'
        save()

        for index, row in enumerate(rows):
            if index == 10:
                print('10/20 photos staged; waiting for the operator write-rate window', flush=True)
                time.sleep(61 - datetime.now(timezone.utc).second)
            photo_bytes = Path(row['image_path']).read_bytes()
            if hashlib.sha256(photo_bytes).hexdigest() != row['sha256']:
                raise RuntimeError('Local photo hash changed: ' + row['asset_id'])
            photo_key = str(UUID(row['sha256'][:32]))
            pet = pet_by_asset[row['asset_id']]
            photo = rpc('seed_begin_photo', {'p_pet': pet, 'p_key': photo_key,
                                             'p_title': row['asset_id'] + ' / ' + row['photographer']})
            state['photos'].append(photo['id'])
            save()
            if photo['state'] != 'ready':
                status, _ = client.call('/storage/v1/object/family-originals/' + photo['path'],
                                        role='operator', raw=photo_bytes)
                if status not in (200, 201):
                    raise RuntimeError('Private photo upload failed (' + str(status) + ')')
                assert rpc('seed_finish_photo', {'p_photo': photo['id']}) is True
            photo_rights_until = (datetime.now(timezone.utc) + timedelta(days=3)).isoformat()
            assert rpc('seed_photo_rights', {
                'p_photo': photo['id'], 'p_holder': row['photographer'],
                'p_scope': 'Pexels licensed image in MEFRION development SNS test only; photograph credit shown in post',
                'p_evidence': row['source_page'] + ' | https://www.pexels.com/license/ | operator permission attestation in .local/pexels-pets/permission.json',
                'p_until': photo_rights_until, 'p_allowed': True,
            }) is True
            body = '【MEFRION運営・検証投稿】\n' + row['body']
            job = rpc('seed_draft', {'p_pet': pet, 'p_photos': [photo['id']], 'p_body': body,
                                     'p_key': str(uuid4())})
            state['jobs'].append(job)
            save()
            assert rpc('seed_approve', {
                'p_job': job, 'p_version': 1,
                'p_rights_note': 'Pexels reference photo, credited in body; test-only use. ' + row['source_page'],
                'p_rights_until': (datetime.now(timezone.utc) + timedelta(days=2)).isoformat(),
            }) is True
            assert rpc('seed_now', {'p_job': job, 'p_version': 2, 'p_explicit': True}) is True

        state['status'] = 'dispatching'
        save()
        dispatched = 0
        state['dispatch_attempts'] = []
        for _ in range(2):
            result = int(privileged('seed_dispatch', {}))
            dispatched += result
            snapshot = rpc('seed_list', {})
            own = [job for pet in snapshot['pets'] if pet['id'] in state['pets'] for job in pet['jobs']]
            counts = {name: sum(job['state'] == name for job in own)
                      for name in ('draft', 'approved', 'scheduled', 'dispatching', 'published', 'stopped')}
            state['dispatch_attempts'].append({'count': result, 'job_states': counts})
            save()
        latest = state['dispatch_attempts'][-1]['job_states']
        if latest['scheduled'] or latest['approved'] or latest['draft'] or latest['stopped'] or latest['dispatching'] + latest['published'] != 20:
            raise RuntimeError('Twenty owned jobs did not enter publication safely: ' + str(latest))
        for _ in range(5):
            worker = subprocess.run([sys.executable, str(ROOT / 'scripts/process_publication_outbox.py')],
                                    check=True, capture_output=True, text=True, timeout=240)
            result = json.loads(worker.stdout)
            if result['failed']:
                raise RuntimeError('Public image worker failed')
            snapshot = rpc('seed_list', {})
            own = [job for pet in snapshot['pets'] if pet['id'] in state['pets'] for job in pet['jobs']]
            if len(own) == 20 and all(job['state'] == 'published' for job in own):
                break
        else:
            raise RuntimeError('Twenty published jobs not verified')
        feed = rpc('feed_page', {'p_limit': 30}, role=None)
        matched = [item for item in feed['items'] if item['pet_id'] in state['pets']]
        if len(matched) != 20 or any(item['likes'] or item['comments'] for item in matched):
            raise RuntimeError('Public feed did not show exactly 20 new zero-engagement posts')
        state['status'] = 'published_verified'
        state['published'] = 20
        state['feed_verified'] = 20
        save()
        print(json.dumps({'status': state['status'], 'published': 20, 'feed_verified': 20,
                          'scope': state['scope']}, ensure_ascii=False))
    except Exception:
        if operator_ready and state['pets']:
            try:
                rpc('seed_stop', {'p_pets': state['pets'], 'p_withdraw_rights': True})
                state['status'] = 'failed_withdrawn'
            except Exception:
                state['status'] = 'failed_cleanup_needed'
        else:
            state['status'] = 'failed_before_publish'
        save()
        raise
    finally:
        if operator_ready:
            subprocess.run([sys.executable, str(ROOT / 'scripts/clean_operator_ui_fixture.py')],
                           check=True, capture_output=True, text=True, timeout=90)


if __name__ == '__main__':
    main()
