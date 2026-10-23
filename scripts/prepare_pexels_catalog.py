"""Verify every local intake image and build an offline, attributed review gallery."""
import argparse
import csv
import hashlib
import html
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

def local_path(root, relative):
    result = (root/relative).resolve()
    if not result.is_relative_to(root.resolve()):
        raise ValueError('Path outside intake folder')
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, default=Path('.local/pexels-pets'))
    args = parser.parse_args()
    root = args.input.resolve()
    rows = [json.loads(line) for line in (root/'manifest.jsonl').read_text().splitlines() if line]
    ids, fingerprints, failures, groups = set(), set(), [], {}
    for row in rows:
        try:
            assert row['species_hint'] in ('dog','cat')
            assert row['asset_id'] not in ids
            assert row['pixel_sha256'] not in fingerprints
            image_path = local_path(root, row['image_path'])
            assert hashlib.sha256(image_path.read_bytes()).hexdigest() == row['sha256']
            with Image.open(image_path) as image:
                image.load()
                assert image.mode == 'RGB'
                assert image.size == (row['width'], row['height'])
                assert max(image.size) <= 1024 and min(image.size) >= 200
                if row.get('jpeg_pixel_sha256'):
                    assert hashlib.sha256(image.tobytes()).hexdigest() == row['jpeg_pixel_sha256']
                assert not image.getexif()
            with Image.open(local_path(root, row['thumbnail_path'])) as thumbnail:
                thumbnail.load()
                assert max(thumbnail.size) <= 320 and thumbnail.mode == 'RGB'
            assert row['source_page'].startswith('https://www.pexels.com/')
            assert row['photographer'] and row['credit'] and row['permission_record']
            assert row['public_post_ready'] is False and row['twins_ground_truth_ready'] is False
            ids.add(row['asset_id']); fingerprints.add(row['pixel_sha256'])
            groups.setdefault(row['species_hint'], []).append(row)
        except Exception as error:
            failures.append({'asset_id':row.get('asset_id'), 'error_type':type(error).__name__})
    report = {'manifest_records':len(rows),'verified_images':len(ids),'failures':failures,
              'checks':['dog/cat category only','unique source ID','unique normalized pixels','SHA-256','JPEG decode',
                        'RGB','dimensions','no EXIF','thumbnail decode','attribution',
                        'local path boundary','publication disabled','ground-truth disabled']}
    (root/'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit(json.dumps(report))
    review = root/'review'
    review.mkdir(exist_ok=True)
    style = '<style>body{font:15px system-ui;background:#fffaf6;color:#222;margin:24px}a{color:#ac2934}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:16px}article{background:white;border:1px solid #edd;border-radius:12px;padding:10px}img{width:100%;height:170px;object-fit:contain}p{overflow-wrap:anywhere;font-size:12px}nav{margin:20px 0}</style>'
    pages = (len(rows)+99)//100
    for page in range(pages):
        parts = ['<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>MEFRION Pexels 素材確認</title>',style,
                 f'<h1>MEFRION 犬・猫の素材確認 {page+1}/{pages}</h1><p>犬・猫の検索分類と説明文で絞り込んだ候補です。全件の目視・個体・犬種・顔の品質は未確認。公開投稿への投入前に確認してください。</p>',
                 '<nav><a href="../index.html">一覧</a> ']
        if page:
            parts.append(f'<a href="page-{page:03d}.html">前へ</a> ')
        if page+1 < pages:
            parts.append(f'<a href="page-{page+2:03d}.html">次へ</a>')
        parts.append('</nav><main class="grid">')
        for row in rows[page*100:(page+1)*100]:
            escape = html.escape
            parts.append(f'<article><a href="../{escape(row["image_path"], quote=True)}"><img loading="lazy" src="../{escape(row["thumbnail_path"], quote=True)}" alt="{escape(row["alt"], quote=True)}"></a><b>{escape(row["asset_id"])}</b><p>仮分類：{escape(row["species_hint"])}</p><p>{escape(row["alt"])}</p><p><a href="{escape(row["source_page"], quote=True)}" rel="noreferrer">{escape(row["credit"])}</a></p></article>')
        parts.append('</main></html>')
        (review/f'page-{page+1:03d}.html').write_text(''.join(parts))
    links = ''.join(f'<li><a href="review/page-{page+1:03d}.html">{page*100+1}–{min((page+1)*100,len(rows))}</a></li>' for page in range(pages))
    (root/'index.html').write_text('<!doctype html><html lang="ja"><meta charset="utf-8"><title>MEFRION 素材一覧</title>'+style+f'<h1>MEFRION Pexels 素材一覧</h1><p>{len(rows):,}件・出典付き・ローカル保存。全画像のファイル検証済み。写真の内容確認・本番公開・Twins正解ラベルは未完了。</p><ul>'+links+'</ul></html>')
    for species, group in groups.items():
        with (root/f'{species}-assets.csv').open('w',newline='') as handle:
            fields = ['asset_id','image_path','thumbnail_path','credit','source_page','species_verified','review_status']
            writer = csv.DictWriter(handle, fieldnames=fields, extrasaction='ignore')
            writer.writeheader(); writer.writerows(group)
    # Text hints only: these are triage aids, never species/rights/quality approval.
    flags = []
    priorities = []
    for row in rows:
        alt = row['alt'].lower()
        people_terms = ('woman', ' man ', 'girl', 'boy', 'child', 'person', 'people', 'owner', 'hand', 'human')
        people = any(term in ' '+alt+' ' for term in people_terms)
        portrait = any(term in alt for term in ('portrait', 'close-up', 'face', 'headshot'))
        flags.append({'asset_id':row['asset_id'], 'possible_person_or_hand':people,
                      'portrait_text_hint':portrait, 'alt':row['alt'],
                      'manual_review_required':True})
        if row['species_hint'] in ('dog','cat') and portrait and not people:
            priorities.append(row)
    (root/'review-hints.jsonl').write_text(''.join(json.dumps(row,ensure_ascii=False)+'\n' for row in flags))
    with (root/'dog-cat-portrait-candidates.csv').open('w',newline='') as handle:
        fields = ['asset_id','species_hint','image_path','thumbnail_path','credit','source_page','alt','review_status']
        writer = csv.DictWriter(handle,fieldnames=fields,extrasaction='ignore')
        writer.writeheader(); writer.writerows(priorities)
    report['dog_cat_portrait_text_candidates'] = len(priorities)
    report['possible_person_or_hand_text_flags'] = sum(row['possible_person_or_hand'] for row in flags)
    (root/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    # Deterministic 8 samples per query category, distributed throughout each group.
    samples = []
    for species, group in sorted(groups.items()):
        samples.extend(group[(i*len(group))//8] for i in range(min(8,len(group))))
    canvas = Image.new('RGB', (1200, ((len(samples)+5)//6)*180), '#fffaf6')
    draw = ImageDraw.Draw(canvas)
    for index,row in enumerate(samples):
        x,y = (index%6)*200,(index//6)*180
        with Image.open(root/row['thumbnail_path']) as image:
            tile = ImageOps.contain(image,(192,148))
            canvas.paste(tile,(x+(200-tile.width)//2,y))
        draw.text((x+5,y+151),f'{row["species_hint"]} / {row["pexels_id"]}',fill='#222')
    canvas.save(root/'contact-sheet.jpg',quality=90)
    (root/'contact-sheet-records.json').write_text(json.dumps(samples,ensure_ascii=False,indent=2))
    print(json.dumps(report,ensure_ascii=False))

if __name__ == '__main__':
    main()
