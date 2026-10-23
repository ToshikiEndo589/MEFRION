"""Resumable local Pexels intake; requires operator-confirmed bulk permission.

Never publishes, creates Pet identities, or embeds an API key in the app.
Run with PEXELS_API_KEY in the environment and --permission-record pointing
to the operator's permission attestation. API responses/images stay local.
"""
import argparse
import concurrent.futures
import csv
import hashlib
import io
import json
import os
import sys
from pathlib import Path
import time
import urllib.error
import urllib.parse
import urllib.request
from PIL import Image, ImageOps
if __package__ in (None, ''):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from scripts.filter_pexels_dog_cat import eligible

QUERIES = [('dog', 'dog'), ('cat', 'cat'), ('dog', 'puppy'), ('cat', 'kitten'),
           ('dog', 'dog portrait'), ('cat', 'cat portrait'),
           ('dog', 'shiba inu'), ('dog', 'golden retriever'), ('dog', 'corgi'),
           ('dog', 'poodle'), ('dog', 'husky'), ('dog', 'dachshund'),
           ('dog', 'labrador'), ('dog', 'beagle'), ('dog', 'chihuahua'),
           ('dog', 'border collie'), ('dog', 'pomeranian'),
           ('cat', 'tabby cat'), ('cat', 'black cat'), ('cat', 'white cat'),
           ('cat', 'orange cat'), ('cat', 'siamese cat'), ('cat', 'persian cat'),
           ('cat', 'ragdoll cat'), ('cat', 'maine coon'), ('cat', 'british shorthair'),
           ('cat', 'sleeping cat'), ('dog', 'sleeping dog')]
QUERIES += [('dog', q) for q in ('bulldog','german shepherd','rottweiler','dalmatian','schnauzer','samoyed','pug','maltese dog','doberman','whippet','greyhound','bichon dog','akita dog','dog face','black dog','white dog','brown dog','dog outdoors')]
QUERIES += [('cat', q) for q in ('bengal cat','sphynx cat','calico cat','tuxedo cat','gray cat','longhair cat','cat face','cat eyes','cat outdoors')]

def safe_url(url, host):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or parsed.hostname != host or parsed.username or parsed.password or parsed.port not in (None, 443):
        raise ValueError('Unexpected source URL')
    return url

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Redirect refused')

def get_bytes(url, headers=None, limit=20_000_000):
    for attempt in range(3):
        try:
            request_headers = {'User-Agent':'MEFRION-AssetIntake/1.0', 'Accept':'application/json' if urllib.parse.urlsplit(url).hostname == 'api.pexels.com' else 'image/*'}
            request_headers.update(headers or {})
            request = urllib.request.Request(url, headers=request_headers)
            with urllib.request.build_opener(NoRedirect()).open(request, timeout=45) as response:
                if urllib.parse.urlsplit(response.url).hostname != urllib.parse.urlsplit(url).hostname:
                    raise ValueError('Unexpected redirect')
                data = response.read(limit + 1)
                if len(data) > limit:
                    raise ValueError('Response exceeds size limit')
                return data, {name.lower():value for name,value in response.headers.items()}
        except urllib.error.HTTPError as error:
            if error.code in (401, 403, 429):
                raise RuntimeError(f'HTTP {error.code}; stopping without credential output') from None
            if attempt == 2:
                raise RuntimeError(f'HTTP {error.code}') from None
        except (TimeoutError, urllib.error.URLError):
            if attempt == 2:
                raise RuntimeError('Network request failed') from None
        time.sleep(2 ** attempt)

def atomic_json(path, value):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2))
    temp.replace(path)

def normalize(data):
    with Image.open(io.BytesIO(data)) as opened:
        if opened.width * opened.height > 80_000_000:
            raise ValueError('Image too large')
        image = ImageOps.exif_transpose(opened).convert('RGB')
        if min(image.size) < 200:
            raise ValueError('Image too small')
        image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        return image.copy()

def dhash(image):
    small = image.convert('L').resize((9, 8))
    pixels = list(small.tobytes())
    value = 0
    for y in range(8):
        for x in range(8):
            value = (value << 1) | (pixels[y*9+x] > pixels[y*9+x+1])
    return f'{value:016x}'

def download(photo, root):
    photo_id = str(int(photo['id']))
    record_path = root/'records'/f'{photo_id}.json'
    if record_path.exists():
        record = json.loads(record_path.read_text())
        if all((root/record[k]).is_file() for k in ('image_path', 'thumbnail_path')):
            return record
    source = safe_url(photo['src']['large'], 'images.pexels.com')
    data, _ = get_bytes(source)
    image = normalize(data)
    image_path = root/'images'/f'{photo_id}.jpg'
    image.save(image_path, quality=88, optimize=True)
    with Image.open(image_path) as jpeg:
        jpeg_pixel_sha256 = hashlib.sha256(jpeg.tobytes()).hexdigest()
    thumb = image.copy()
    thumb.thumbnail((320, 320), Image.Resampling.LANCZOS)
    thumb_path = root/'thumbnails'/f'{photo_id}.jpg'
    thumb.save(thumb_path, quality=82, optimize=True)
    record = {
        'asset_id': f'pexels-{photo_id}', 'pexels_id': int(photo_id),
        'source': 'Pexels', 'source_page': safe_url(photo['url'], 'www.pexels.com'),
        'photographer': photo['photographer'], 'photographer_url': photo['photographer_url'],
        'credit': f"Photo by {photo['photographer']} on Pexels",
        'license_url': 'https://www.pexels.com/license/',
        'permission_record': 'permission.json',
        'permission_basis': 'operator_attested_explicit_pexels_permission',
        'collected_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'download_url': source, 'source_sha256': hashlib.sha256(data).hexdigest(),
        'sha256': hashlib.sha256(image_path.read_bytes()).hexdigest(),
        'pixel_sha256': hashlib.sha256(image.tobytes()).hexdigest(),
        'jpeg_pixel_sha256': jpeg_pixel_sha256,
        'dhash': dhash(image), 'width': image.width, 'height': image.height,
        'image_path': str(image_path.relative_to(root)),
        'thumbnail_path': str(thumb_path.relative_to(root)),
        'alt': photo.get('alt', ''), 'query_tags': photo['_query_tags'],
        'species_hint': photo['_species_hint'], 'species_verified': False,
        'individual_identity': None, 'breed': None,
        'review_status': 'pending_visual_review', 'public_post_ready': False,
        'twins_ground_truth_ready': False,
    }
    atomic_json(record_path, record)
    return record

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=Path('.local/pexels-pets'))
    parser.add_argument('--target', type=int, default=6000)
    parser.add_argument('--request-budget', type=int, default=160)
    parser.add_argument('--permission-record', type=Path, required=True)
    args = parser.parse_args()
    key = os.environ.get('PEXELS_API_KEY', '').strip()
    if not key:
        raise SystemExit('PEXELS_API_KEY is required')
    permission = json.loads(args.permission_record.read_text())
    if permission.get('operator_confirmed_explicit_permission') is not True:
        raise SystemExit('Explicit permission attestation is required')
    root = args.output
    for folder in ('responses', 'records', 'images', 'thumbnails'):
        (root/folder).mkdir(parents=True, exist_ok=True)
    atomic_json(root/'permission.json', permission)
    photos = {}
    request_count = 0
    quota_stopped = False
    exhausted = set()
    for page in range(1, 30):
        for species, query in QUERIES:
            if query in exhausted:
                continue
            cache = root/'responses'/f'{query.replace(" ", "-")}-{page}.json'
            if cache.exists():
                response = json.loads(cache.read_text())
            else:
                if request_count >= args.request_budget:
                    exhausted.add(query)
                    continue
                url = 'https://api.pexels.com/v1/search?' + urllib.parse.urlencode({'query':query, 'page':page, 'per_page':80, 'locale':'en-US'})
                try:
                    payload, headers = get_bytes(url, {'Authorization':key}, limit=5_000_000)
                except RuntimeError as error:
                    if 'HTTP 429' not in str(error): raise
                    quota_stopped = True
                    break
                request_count += 1
                response = json.loads(payload)
                atomic_json(cache, response)
                atomic_json(root/'rate-limit.json', {'requests_this_run':request_count,
                    'remaining':headers.get('x-ratelimit-remaining'),
                    'reset':headers.get('x-ratelimit-reset')})
                time.sleep(0.35)
            entries = response.get('photos', [])
            if not entries:
                exhausted.add(query)
            for photo in entries:
                allowed, _ = eligible({'species_hint':species,'alt':photo.get('alt','')})
                if not allowed:
                    continue
                photo_id = int(photo['id'])
                if photo_id in photos:
                    if query not in photos[photo_id]['_query_tags']:
                        photos[photo_id]['_query_tags'].append(query)
                else:
                    photo['_query_tags'] = [query]
                    photo['_species_hint'] = species
                    photos[photo_id] = photo
            print(json.dumps({'phase':'search','query':query,'page':page,'unique_ids':len(photos),'requests':request_count}), flush=True)
            if len(photos) >= args.target + 300:
                break
        if quota_stopped or len(photos) >= args.target + 300 or len(exhausted) == len(QUERIES):
            break
    atomic_json(root/'candidate-index.json', list(photos.values()))
    # A quota stop or partial new search must never remove the existing library.
    prior = root/'manifest.jsonl'
    records = [json.loads(line) for line in prior.read_text().splitlines()] if prior.exists() else []
    records = [row for row in records if eligible(row)[0]]
    errors, duplicates = [], []
    fingerprints = {row['pixel_sha256'] for row in records}
    existing_ids = {row['pexels_id'] for row in records}
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        futures = {pool.submit(download, photo, root):photo['id'] for photo in photos.values() if photo['id'] not in existing_ids}
        for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
            try:
                record = future.result()
                fingerprint = record['pixel_sha256']
                if fingerprint in fingerprints:
                    duplicates.append(record['asset_id'])
                else:
                    fingerprints.add(fingerprint)
                    records.append(record)
            except Exception as error:
                errors.append({'pexels_id':futures[future], 'error_type':type(error).__name__})
            if index % 100 == 0:
                print(json.dumps({'phase':'download','completed':index,'accepted':len(records),'failed':len(errors),'duplicates':len(duplicates)}), flush=True)
    records.sort(key=lambda row:row['pexels_id'])
    with (root/'manifest.jsonl').open('w') as handle:
        for row in records:
            handle.write(json.dumps(row, ensure_ascii=False)+'\n')
    columns = ['asset_id','species_hint','image_path','thumbnail_path','width','height','photographer','source_page','credit','review_status','sha256']
    with (root/'manifest.csv').open('w', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction='ignore')
        writer.writeheader(); writer.writerows(records)
    counts = {}
    for row in records:
        counts[row['species_hint']] = counts.get(row['species_hint'],0)+1
    summary = {'requested_target':args.target,'candidate_ids':len(photos),'collected_unique_images':len(records),
               'exact_duplicates_excluded':len(duplicates),'failures':errors,
               'species_query_hints':counts,'search_requests_this_run':request_count,
               'cached_response_pages':len(list((root/'responses').glob('*.json'))),
               'quota_stopped':quota_stopped,
               'all_pending_visual_review':True,'published':False,
               'bytes_on_disk':sum(p.stat().st_size for p in root.rglob('*') if p.is_file())}
    atomic_json(root/'summary.json', summary)
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    if len(records) < args.target:
        raise SystemExit('Target not reached; partial collection preserved for resume')

if __name__ == '__main__':
    main()
