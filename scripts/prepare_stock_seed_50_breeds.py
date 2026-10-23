"""Prepare reviewed, photo-specific breed labels for the 50 dev seed posts.

Only an explicit breed in the saved Pexels alt text is used. Search terms,
coat patterns, and visual guesses are not treated as breed evidence.
"""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROWS = ROOT / 'release/stock-seed-plan/queue.csv'
OUT = ROOT / 'release/stock-seed-plan/stock-50-breeds.sql'
STATE = ROOT / '.local/stock-seed-test-50-20261015.json'

# Pexels asset ID -> (phrase required in saved alt text, Japanese display label).
EXPLICIT = {
    '9000268': ('Shiba Inu', '柴犬（推定）'),
    '33238049': ('Maine Coon', 'メインクーン（推定）'),
    '10802076': ('Dalmatian', 'ダルメシアン（推定）'),
    '604680': ('chihuahua', 'チワワ（推定）'),
    '35708991': ('Siamese', 'シャム（推定）'),
    '19216488': ('corgis', 'ウェルシュ・コーギー（推定）'),
    '10096129': ('golden retriever', 'ゴールデン・レトリーバー（推定）'),
    '32740130': ('Rhodesian Ridgeback', 'ローデシアン・リッジバック（推定）'),
    '33146632': ('Ragdoll', 'ラグドール（推定）'),
    '14530396': ('Shiba Inu', '柴犬（推定）'),
    '14304586': ('Persian', 'ペルシャ（推定）'),
    '27939375': ('German Shepherd mix', 'ジャーマン・シェパード系ミックス（推定）'),
    '35279223': ('British Shorthair', 'ブリティッシュショートヘア（推定）'),
    '14839095': ('corgi', 'ウェルシュ・コーギー（推定）'),
    '34490255': ('Chihuahua', 'チワワ（推定）'),
    '35058642': ('Rottweiler', 'ロットワイラー（推定）'),
    '14639088': ('Maine Coon', 'メインクーン（推定）'),
    '6234629': ('Rough Collie', 'ラフ・コリー（推定）'),
    '28448365': ('British Shorthair', 'ブリティッシュショートヘア（推定）'),
    '23542061': ('Miniature Schnauzer', 'ミニチュア・シュナウザー（推定）'),
    '16738458': ('Labrador Retriever', 'ラブラドール・レトリーバー（推定）'),
    '36581981': ('German Shepherd', 'ジャーマン・シェパード（推定）'),
    '9630275': ('Persian', 'ペルシャ（推定）'),
    '7534057': ('Pomeranian', 'ポメラニアン（推定）'),
    '33373209': ('Bengal', 'ベンガル（推定）'),
    '35694587': ('Ragdoll', 'ラグドール（推定）'),
}


def sql(value):
    return "'" + str(value).replace("'", "''") + "'"


def main():
    state = json.loads(STATE.read_text())
    if state['status'] != 'published_verified' or len(state['pets']) != 2:
        raise RuntimeError('Expected exactly two verified development collection accounts')
    dog_id, cat_id = state['pets']
    rows = list(csv.DictReader(ROWS.open(newline='')))[20:70]
    if len(rows) != 50 or len({r['asset_id'] for r in rows}) != 50:
        raise RuntimeError('Expected 50 distinct seed assets')
    labels = []
    for row in rows:
        asset_id = row['asset_id'].split('-', 1)[1]
        record = json.loads((ROOT / '.local/pexels-pets/records' / (asset_id + '.json')).read_text())
        if record['source_page'] != row['source_page'] or record['species_hint'] != row['species']:
            raise RuntimeError(f'Source mismatch: {asset_id}')
        if asset_id in EXPLICIT:
            phrase, label = EXPLICIT[asset_id]
            if phrase.casefold() not in record['alt'].casefold():
                raise RuntimeError(f'Breed phrase missing from saved alt text: {asset_id}')
        else:
            label = '犬種未確認' if row['species'] == 'dog' else '猫種未確認'
        labels.append((row['asset_id'], label, row['species']))
    if {int(asset) for asset in EXPLICIT} - {int(r['asset_id'].split('-', 1)[1]) for r in rows}:
        raise RuntimeError('Curated breed map includes an asset outside this 50-post run')
    values = ',\n'.join('  (' + ', '.join(sql(item) for item in label) + ')' for label in labels)
    script = f"""-- Development-only guarded update for the approved 50-post run.
-- Labels come from saved Pexels alt text; unverified breeds remain unverified.
-- This changes account display names and per-post breed metadata only.
begin;
create temporary table stock50_labels(asset_id text primary key, breed_label text not null, species text not null) on commit drop;
insert into stock50_labels(asset_id,breed_label,species) values
{values};
do $$
begin
 if (select count(*) from stock50_labels) <> 50 then raise exception 'Expected 50 labels'; end if;
 if (select count(*) from mefrion_private.pets p where
      (p.id='{dog_id}'::uuid and p.species='dog' and p.name in ('MEFRIONセレクト犬・検証','わんこ日和')) or
      (p.id='{cat_id}'::uuid and p.species='cat' and p.name in ('MEFRIONセレクト猫・検証','にゃんこ日和'))) <> 2 then
   raise exception 'Managed collection accounts changed';
 end if;
 if (select count(*) from stock50_labels l
      join mefrion_private.photos ph on ph.title like l.asset_id || ' / %'
      join mefrion_private.public_media m on m.source_id=ph.id
      join mefrion_private.public_posts s on s.id=m.post_id
      join mefrion_private.pets p on p.id=s.pet_id and p.species=l.species
      where s.content_origin='managed_seed' and s.state='published'
        and s.pet_id in ('{dog_id}'::uuid,'{cat_id}'::uuid)) <> 50 then
   raise exception 'Expected 50 matching published photos';
 end if;
end $$;
update mefrion_private.pets set name='わんこ日和',breed='さまざまな犬種'
 where id='{dog_id}'::uuid;
update mefrion_private.pets set name='にゃんこ日和',breed='さまざまな猫種'
 where id='{cat_id}'::uuid;
update mefrion_private.public_posts s set breed_label=l.breed_label
 from stock50_labels l
 join mefrion_private.photos ph on ph.title like l.asset_id || ' / %'
 join mefrion_private.public_media m on m.source_id=ph.id
 where s.id=m.post_id and s.content_origin='managed_seed' and s.state='published'
   and s.pet_id in ('{dog_id}'::uuid,'{cat_id}'::uuid);
do $$
begin
 if (select count(*) from mefrion_private.public_posts s
     where s.pet_id in ('{dog_id}'::uuid,'{cat_id}'::uuid)
       and s.state='published' and s.breed_label is not null) <> 50 then
   raise exception 'Not all 50 posts were labelled';
 end if;
end $$;
insert into mefrion_private.audit(pet_id,action) values
 ('{dog_id}'::uuid,'seed.collection_name_and_breed_labels'),
 ('{cat_id}'::uuid,'seed.collection_name_and_breed_labels');
commit;
select p.name,p.species,count(*) as labelled_posts from mefrion_private.pets p
 join mefrion_private.public_posts s on s.pet_id=p.id and s.state='published' and s.breed_label is not null
 where p.id in ('{dog_id}'::uuid,'{cat_id}'::uuid)
 group by p.name,p.species order by p.species;
"""
    OUT.write_text(script)
    print(json.dumps({'output': str(OUT), 'total': len(labels),
                      'source_breed': len(EXPLICIT), 'unverified': len(labels) - len(EXPLICIT)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
