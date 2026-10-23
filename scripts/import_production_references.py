"""Add existing licensed stock descriptors/thumbs to production, with resume.

No user, family album, password, reaction or publication is copied from dev.
Withdrawn assets are never reactivated; activation requires an uploaded object.
"""
import base64
import concurrent.futures
import json
import struct
import time
import urllib.error
import urllib.request
from pathlib import Path

from import_reference_index import validate
from production_admin import ROOT, LOCAL, connect


def main():
    index = LOCAL / 'TwinsServerIndex'
    catalog = json.loads((index / 'catalog.json').read_text())
    assets = catalog['assets']; raw = (index / 'vectors.bin').read_bytes()
    assert catalog['revision'] == 2 and catalog['elements'] == 768 and len(raw) == len(assets) * 768 * 4
    for asset in assets:
        validate(asset)
    total = sum((index / 'images' / asset['file']).stat().st_size for asset in assets)
    assert total < 450_000_000
    c = connect()
    try:
        existing = {row[0] for row in c.run('select id from public.mefrion_reference_assets where active or withdrawn_at is not null')}
        selected = [(i, a) for i, a in enumerate(assets) if a['id'] not in existing]
        for start in range(0, len(selected), 100):
            rows = []
            for i, a in selected[start:start+100]:
                rows.append({**a, 'embedding': str(list(struct.unpack_from('<768f', raw, i*768*4)))})
            c.run("""insert into public.mefrion_reference_assets(id,species,file,credit,source,embedding,fingerprint,mean)
              select id,species,file,credit,source,embedding::extensions.vector,fingerprint::bit(144),mean
              from jsonb_to_recordset(:rows::jsonb) as t(id text,species text,file text,credit text,source text,embedding text,fingerprint text,mean real)
              on conflict(id) do nothing""", rows=json.dumps(rows))
        native = json.loads((LOCAL / 'resemblance/native-catalog.json').read_text())
        vectors = (LOCAL / 'resemblance/native-vectors.bin').read_bytes()
        assert native['elements'] == 384 and len(vectors) == len(native['assets']) * 384 * 4
        present = {row[0] for row in c.run('select id from public.mefrion_reference_resemblance')}
        for start in range(0, len(native['assets']), 100):
            rows = []
            for i, a in enumerate(native['assets'][start:start+100], start):
                if a['id'] in present: continue
                rows.append({'id': a['id'], 'species': a['species'], 'embedding': str(list(struct.unpack_from('<384f', vectors, i*384*4))), 'color': str(a['color']), 'crop_kind': a['kind']})
            if rows:
                c.run("""insert into public.mefrion_reference_resemblance(id,species,algorithm,embedding,color,crop_kind)
                  select id,species,'dinov2-small-subject-v1',embedding::extensions.vector,color::extensions.vector,crop_kind
                  from jsonb_to_recordset(:rows::jsonb) as t(id text,species text,embedding text,color text,crop_kind text)
                  on conflict(id) do nothing""", rows=json.dumps(rows))
        token = (LOCAL / 'production-cloud-worker-token').read_text().strip()
        def upload(batch):
            body = json.dumps({'items': [{'path': a['file'], 'bytes': base64.b64encode((index/'images'/a['file']).read_bytes()).decode()} for _, a in batch]}).encode()
            for attempt in range(4):
                try:
                    request = urllib.request.Request('https://pbnimpqrthvznbwewtcf.supabase.co/functions/v1/asset-ingest', data=body, headers={'Content-Type': 'application/json', 'x-mefrion-worker': token})
                    with urllib.request.urlopen(request, timeout=120) as response: result = json.load(response)
                    if result.get('failed'): raise RuntimeError('Stock upload incomplete')
                    return [name[:-4] for name in result['uploaded']]
                except (OSError, ValueError, RuntimeError):
                    if attempt == 3: raise RuntimeError('Stock upload failed; resume is safe') from None
                    time.sleep(2**attempt)
        uploaded = 0
        # Keep only a bounded window of pending uploads; never hold all image
        # bytes in memory. SQL activation is serialized through one connection.
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            for offset in range(0, len(selected), 400):
                window = selected[offset:offset+400]
                futures = [pool.submit(upload, window[i:i+20]) for i in range(0, len(window), 20)]
                for future in concurrent.futures.as_completed(futures):
                    ids = future.result(); uploaded += len(ids)
                    c.run('select public.mefrion_reference_activate(:ids)', ids=ids)
                print(json.dumps({'already_active_or_withdrawn': len(existing), 'uploaded': uploaded, 'target': len(selected)}), flush=True)
        report = {'assets': c.run('select count(*) from public.mefrion_reference_assets where active and withdrawn_at is null')[0][0],
                  'descriptors': c.run('select count(*) from public.mefrion_reference_resemblance')[0][0],
                  'database_bytes': c.run('select pg_database_size(current_database())')[0][0], 'stock_image_bytes': total,
                  'copied_customer_accounts_or_photos': False}
        (ROOT/'docs/evidence/PRODUCTION-REFERENCE-IMPORT.json').write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps(report), flush=True)
    finally:
        c.close()


if __name__ == '__main__': main()
