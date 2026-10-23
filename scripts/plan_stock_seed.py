"""Prepare auditable Pexels-backed MEFRION seed queues; never publish photos.

The plan is stable for a frozen candidate CSV. Activation, individual image review,
rights recording, and upload remain separate from this offline planning step.
"""
import argparse
import csv
import hashlib
import json
import re
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

try:
    from .stock_pet_names import name_for
    from .prepare_stock_seed_50_breeds import EXPLICIT
except ImportError:  # Direct invocation: python3 scripts/plan_stock_seed.py
    from stock_pet_names import name_for
    from prepare_stock_seed_50_breeds import EXPLICIT

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / '.local/pexels-pets'
UNSUITABLE = re.compile(r'\b(?:man|woman|men|women|people|person|girl|boy|child|children|human|mural|painting|drawing|sculpture|statue|toy|plush|cartoon|illustration|lingerie|nude)\b', re.I)


def load_candidates(source=SOURCE):
    metadata = {row['asset_id']: row for row in csv.DictReader((source / 'manifest.csv').open(newline=''))}
    classified = json.loads((ROOT / '.local/resemblance/catalog.json').read_text())['assets']
    descriptions = {f"pexels-{item['id']}": item.get('alt', '') for item in json.loads((source / 'candidate-index.json').read_text())}
    chosen = {'dog': [], 'cat': []}
    seen_hashes = set()
    for asset in classified:
        item = metadata.get(asset['id'])
        if (not item or asset['id'] == 'pexels-1790445' or
                asset['species'] not in chosen or item['species_hint'] != asset['species'] or
                asset.get('kind') not in ('animal', 'head') or
                item['source_page'] != asset['source'] or
                UNSUITABLE.search(descriptions.get(asset['id'], ''))):
            continue
        photo = source / item['image_path']
        if not photo.is_file() or not item['source_page'].startswith('https://www.pexels.com/photo/'):
            continue
        digest = hashlib.sha256(photo.read_bytes()).hexdigest()
        if digest != item['sha256'] or digest in seen_hashes:
            continue
        seen_hashes.add(digest)
        chosen[item['species_hint']].append({
            'asset_id': item['asset_id'], 'species': item['species_hint'],
            'image_path': str(photo.resolve()), 'sha256': digest,
            'source_page': item['source_page'], 'photographer': item['photographer'],
            'credit': item['credit'],
            'alt': descriptions.get(asset['id'], ''),
            'composition': asset['kind'],
            'review_status': item['review_status'],
        })
    for species in chosen:
        chosen[species].sort(key=lambda item: (
            item['composition'] != 'head',
            hashlib.sha256(('mefrion-seed-v1:' + item['asset_id']).encode()).hexdigest(),
        ))
    return chosen


def build_plan(chosen, start_date, days):
    if days < 1:
        raise ValueError('days must be positive')
    count = 100 + 30 * days
    if min(len(chosen['dog']), len(chosen['cat'])) < count // 2:
        raise ValueError('not enough unique dog and cat photos for requested horizon')
    entries = []
    for index in range(count):
        species = 'dog' if index % 2 == 0 else 'cat'
        photo = chosen[species][index // 2]
        batch = 'initial' if index < 100 else 'daily'
        day = 0 if index < 100 else 1 + (index - 100) // 30
        planned = start_date + timedelta(days=day)
        slot = time(hour=10, minute=index // 10) if day == 0 else time(hour=(9, 13, 18)[((index - 100) % 30) // 10], minute=(index - 100) % 10)
        publication_at = datetime.combine(planned, slot, timezone(timedelta(hours=9))).isoformat()
        asset_number = photo['asset_id'].split('-', 1)[-1]
        evidence = EXPLICIT.get(asset_number)
        breed = evidence[1].replace('（推定）', '') if evidence and evidence[0].casefold() in photo.get('alt', '').casefold() else ''
        pet_name = name_for(species, index // 2)
        entries.append({
            'seed_id': f'SEED-{index + 1:05d}', 'batch': batch,
            'publication_date': planned.isoformat(),
            'publication_at': publication_at,
            'pet_profile_key': 'stock-individual-' + photo['asset_id'],
            'pet_name': pet_name,
            'pet_breed': breed,
            'display_account': pet_name,
            'body': f'運営セレクトの参考写真です。撮影: {photo["photographer"]} / Pexels\n{photo["source_page"]}',
            'rights_state': 'pending_individual_review',
            **photo,
        })
    return entries


def write_plan(entries, destination, source=SOURCE):
    destination.mkdir(parents=True, exist_ok=True)
    with (destination / 'queue.jsonl').open('w') as target:
        for item in entries:
            target.write(json.dumps(item, ensure_ascii=False) + '\n')
    fields = ['seed_id', 'batch', 'publication_date', 'publication_at', 'species', 'composition', 'asset_id', 'image_path',
              'sha256', 'source_page', 'photographer', 'credit', 'review_status',
              'rights_state', 'pet_profile_key', 'pet_name', 'pet_breed', 'display_account', 'body']
    with (destination / 'queue.csv').open('w', newline='') as target:
        writer = csv.DictWriter(target, fieldnames=fields, extrasaction='ignore')
        writer.writeheader()
        writer.writerows(entries)
    with (destination / 'managed-pets.csv').open('w', newline='') as target:
        writer = csv.DictWriter(target, fieldnames=['key', 'name', 'species', 'breed', 'introduction', 'source'])
        writer.writeheader()
        writer.writerows({'key': item['pet_profile_key'], 'name': item['pet_name'],
                          'species': item['species'], 'breed': item['pet_breed'],
                          'introduction': '', 'source': item['source_page']} for item in entries)
    meta = {
        'source': str((ROOT / '.local/resemblance/catalog.json').resolve()),
        'source_sha256': hashlib.sha256((ROOT / '.local/resemblance/catalog.json').read_bytes()).hexdigest(),
        'initial_count': sum(item['batch'] == 'initial' for item in entries),
        'daily_count': 30, 'days_prepared': (len(entries) - 100) // 30,
        'first_date': entries[0]['publication_date'],
        'last_date': entries[-1]['publication_date'],
        'status': 'offline_plan_only_not_approved_or_published',
        'policy': 'One managed Pet profile per photo. No real owner claim, invented biography, likes or comments.',
    }
    (destination / 'plan.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n')
    return meta


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--start-date', type=date.fromisoformat, required=True)
    parser.add_argument('--days', type=int, default=365)
    parser.add_argument('--output', type=Path, default=ROOT / 'release/stock-seed-plan')
    args = parser.parse_args()
    meta = write_plan(build_plan(load_candidates(), args.start_date, args.days), args.output)
    print(json.dumps(meta, ensure_ascii=False))


if __name__ == '__main__':
    main()
