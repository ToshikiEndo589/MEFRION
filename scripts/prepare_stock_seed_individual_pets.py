"""Prepare a guarded one-photo/one-Pet migration for the approved 50 dev posts.

Names identify the animal in each reference photo. They do not assert a real
owner, history, pedigree, or a second human account. Unknown breeds stay blank.
"""
import csv
import json
from pathlib import Path

from prepare_stock_seed_50_breeds import EXPLICIT, sql
from stock_pet_names import DOG_NAMES, CAT_NAMES

ROOT = Path(__file__).resolve().parents[1]
ROWS = ROOT / 'release/stock-seed-plan/queue.csv'
STATE = ROOT / '.local/stock-seed-test-50-20261015.json'
OUT = ROOT / 'release/stock-seed-plan/stock-50-individual-pets.sql'

def main():
    state = json.loads(STATE.read_text())
    if state['status'] != 'published_verified' or len(state['pets']) != 2 or len(state['asset_ids']) != 50:
        raise RuntimeError('Expected the verified 50-post development run')
    dog_id, cat_id = state['pets']
    rows = list(csv.DictReader(ROWS.open(newline='')))[20:70]
    if len(rows) != 50 or [r['asset_id'] for r in rows] != state['asset_ids']:
        raise RuntimeError('The source queue differs from the published run')
    if len(set(DOG_NAMES + CAT_NAMES)) != 50:
        raise RuntimeError('Animal names must be distinct in this run')
    indexes = {'dog': 0, 'cat': 0}
    prepared = []
    for row in rows:
        species = row['species']
        names = DOG_NAMES if species == 'dog' else CAT_NAMES
        index = indexes[species]
        if index >= len(names):
            raise RuntimeError('Unexpected species distribution')
        indexes[species] += 1
        asset = row['asset_id'].split('-', 1)[1]
        record = json.loads((ROOT / '.local/pexels-pets/records' / (asset + '.json')).read_text())
        if record['source_page'] != row['source_page'] or record['species_hint'] != species:
            raise RuntimeError('Source mismatch: ' + asset)
        breed = ''
        if asset in EXPLICIT:
            phrase, label = EXPLICIT[asset]
            if phrase.casefold() not in record['alt'].casefold():
                raise RuntimeError('Unverified breed: ' + asset)
            breed = label.replace('（推定）', '')
        prepared.append((row['asset_id'], names[index], species, breed))
    if indexes != {'dog': 25, 'cat': 25}:
        raise RuntimeError('Expected 25 dogs and 25 cats')
    values = ',\n'.join('  (' + ', '.join(sql(x) for x in item) + ')' for item in prepared)
    statement = f"""-- Approved Free development project only. Preserve every post/media/rights ID.
-- One independent Pet profile per photograph. No invented human user accounts.
-- Breed is blank if the saved source description does not identify one.
begin;
create temporary table stock_individual (
 asset_id text primary key, pet_name text unique not null, species text not null,
 breed text not null, old_pet_id uuid, photo_id uuid, post_id uuid,
 job_id uuid, new_pet_id uuid unique
) on commit drop;
insert into stock_individual(asset_id,pet_name,species,breed) values
{values};

do $$
declare n integer; p integer; ph integer; j integer;
begin
 if (select count(*) from stock_individual) <> 50 then raise exception 'expected 50 identities';end if;
 select count(*),count(distinct s.id),count(distinct photo.id),count(distinct job.id)
 into n,p,ph,j
 from stock_individual item
 join mefrion_private.photos photo on photo.title like item.asset_id || ' / %'
 join mefrion_private.public_media media on media.source_id=photo.id and media.position=0
 join mefrion_private.public_posts s on s.id=media.post_id
 join mefrion_private.seed_jobs job on job.post_id=s.id and job.photos=array[photo.id]
 where s.state='published' and s.content_origin='managed_seed' and job.state='published'
   and s.pet_id=photo.pet_id and job.pet_id=s.pet_id
   and s.pet_id=case item.species when 'dog' then '{dog_id}'::uuid else '{cat_id}'::uuid end;
 if n<>50 or p<>50 or ph<>50 or j<>50 then raise exception 'published source mapping changed: %,%,%,%',n,p,ph,j;end if;
 if (select count(*) from mefrion_private.public_posts where pet_id in ('{dog_id}'::uuid,'{cat_id}'::uuid) and state='published')<>50 then raise exception 'source account post count changed';end if;
 if exists(select 1 from mefrion_private.follows where pet_id in ('{dog_id}'::uuid,'{cat_id}'::uuid)) then raise exception 'collection followers require a separate migration plan';end if;
 if (select count(*) from mefrion_private.photos where pet_id in ('{dog_id}'::uuid,'{cat_id}'::uuid) and state='ready')<>50 then raise exception 'collection photo count changed';end if;
 if exists(select 1 from mefrion_private.seed_jobs where pet_id in ('{dog_id}'::uuid,'{cat_id}'::uuid) and state<>'published') then raise exception 'collection has another active or stopped job';end if;
end $$;

update stock_individual item set old_pet_id=s.pet_id,photo_id=photo.id,post_id=s.id,
 job_id=job.id,new_pet_id=gen_random_uuid()
from mefrion_private.photos photo
join mefrion_private.public_media media on media.source_id=photo.id and media.position=0
join mefrion_private.public_posts s on s.id=media.post_id
join mefrion_private.seed_jobs job on job.post_id=s.id and job.photos=array[photo.id]
where photo.title like item.asset_id || ' / %'
 and s.pet_id=case item.species when 'dog' then '{dog_id}'::uuid else '{cat_id}'::uuid end;

do $$ begin
 if (select count(*) from stock_individual where old_pet_id is not null and photo_id is not null and post_id is not null and job_id is not null and new_pet_id is not null)<>50 then raise exception 'incomplete identity map';end if;
end $$;

insert into mefrion_private.pets(id,owner_id,name,species,breed,introduction,public_fields)
select item.new_pet_id,old.owner_id,item.pet_name,item.species,item.breed,'',array['breed']::text[]
from stock_individual item join mefrion_private.pets old on old.id=item.old_pet_id;

insert into mefrion_private.managed_pets
 (pet_id,publisher_id,external_key,source_note,rights_note,rights_until,rights_verified,active,updated_by)
select item.new_pet_id,old.publisher_id,'stock-individual-'||item.asset_id,
 old.source_note,old.rights_note,old.rights_until,old.rights_verified,old.active,old.updated_by
from stock_individual item join mefrion_private.managed_pets old on old.pet_id=item.old_pet_id;

-- The migration has no user JWT; preserve all other profile triggers.
alter table mefrion_private.public_profiles disable trigger mefrion_public_profile_write;
insert into mefrion_private.public_profiles(pet_id,enabled)
select new_pet_id,true from stock_individual;
alter table mefrion_private.public_profiles enable trigger mefrion_public_profile_write;

update mefrion_private.photos photo set pet_id=item.new_pet_id
from stock_individual item where photo.id=item.photo_id;
update mefrion_private.seed_jobs job set pet_id=item.new_pet_id,version=job.version+1
from stock_individual item where job.id=item.job_id;
update mefrion_private.public_posts post set pet_id=item.new_pet_id,breed_label=null
from stock_individual item where post.id=item.post_id;
update mefrion_private.post_pet_tags tag set pet_id=item.new_pet_id
from stock_individual item where tag.post_id=item.post_id and tag.pet_id=item.old_pet_id;

do $$
declare visible integer;
begin
 if (select count(*) from stock_individual item
     join mefrion_private.public_posts post on post.id=item.post_id and post.pet_id=item.new_pet_id and post.state='published'
     join mefrion_private.photos photo on photo.id=item.photo_id and photo.pet_id=item.new_pet_id
     join mefrion_private.seed_jobs job on job.id=item.job_id and job.pet_id=item.new_pet_id and job.state='published'
     join mefrion_private.managed_pets managed on managed.pet_id=item.new_pet_id and managed.rights_verified and managed.active
     join mefrion_private.public_profiles profile on profile.pet_id=item.new_pet_id and profile.enabled)<>50 then raise exception 'individual profile integrity failed';end if;
 select count(*) into visible from stock_individual item where mefrion_private.post_allowed(item.post_id,null);
 if visible<>50 then raise exception 'some posts are no longer public: %',visible;end if;
end $$;
insert into mefrion_private.audit(pet_id,action)
select new_pet_id,'seed.one_photo_one_pet' from stock_individual;
commit;

select count(*) as posts,count(distinct post.pet_id) as named_pets,
 count(*) filter(where pet.breed<>'') as breeds_shown,
 count(*) filter(where pet.breed='') as breeds_hidden
from mefrion_private.public_posts post
join mefrion_private.pets pet on pet.id=post.pet_id
join mefrion_private.managed_pets managed on managed.pet_id=pet.id
where post.content_origin='managed_seed' and post.state='published'
 and managed.external_key like 'stock-individual-%';
"""
    OUT.write_text(statement)
    print(json.dumps({'output': str(OUT), 'posts': len(prepared), 'names': len(set(item[1] for item in prepared)),
                      'breeds_shown': sum(bool(item[3]) for item in prepared),
                      'breeds_hidden': sum(not item[3] for item in prepared)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
