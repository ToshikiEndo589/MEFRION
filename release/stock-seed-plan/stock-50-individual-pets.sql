-- Approved Free development project only. Preserve every post/media/rights ID.
-- One independent Pet profile per photograph. No invented human user accounts.
-- Breed is blank if the saved source description does not identify one.
begin;
create temporary table stock_individual (
 asset_id text primary key, pet_name text unique not null, species text not null,
 breed text not null, old_pet_id uuid, photo_id uuid, post_id uuid,
 job_id uuid, new_pet_id uuid unique
) on commit drop;
insert into stock_individual(asset_id,pet_name,species,breed) values
  ('pexels-9000268', 'こむぎ', 'dog', '柴犬'),
  ('pexels-33238049', 'つむぎ', 'cat', 'メインクーン'),
  ('pexels-34584041', 'まる', 'dog', ''),
  ('pexels-29102292', 'もち', 'cat', ''),
  ('pexels-10802076', 'そら', 'dog', 'ダルメシアン'),
  ('pexels-27505369', 'みるく', 'cat', ''),
  ('pexels-604680', 'レオ', 'dog', 'チワワ'),
  ('pexels-35708991', 'こはく', 'cat', 'シャム'),
  ('pexels-19216488', 'モカ', 'dog', 'ウェルシュ・コーギー'),
  ('pexels-34760125', 'あずき', 'cat', ''),
  ('pexels-10096129', 'はる', 'dog', 'ゴールデン・レトリーバー'),
  ('pexels-33331606', 'ルナ', 'cat', ''),
  ('pexels-32740130', 'だいふく', 'dog', 'ローデシアン・リッジバック'),
  ('pexels-33146632', 'すず', 'cat', 'ラグドール'),
  ('pexels-15175669', 'くう', 'dog', ''),
  ('pexels-33495875', 'きなこ', 'cat', ''),
  ('pexels-14530396', 'コロ', 'dog', '柴犬'),
  ('pexels-14304586', 'しらたま', 'cat', 'ペルシャ'),
  ('pexels-27939375', 'ふうた', 'dog', 'ジャーマン・シェパード系ミックス'),
  ('pexels-39024568', 'めい', 'cat', ''),
  ('pexels-14148741', 'ぽんず', 'dog', ''),
  ('pexels-39563705', 'くるみ', 'cat', ''),
  ('pexels-13026253', 'むぎ', 'dog', ''),
  ('pexels-35279223', 'ちょこ', 'cat', 'ブリティッシュショートヘア'),
  ('pexels-16623448', 'ルーク', 'dog', ''),
  ('pexels-38497229', 'にこ', 'cat', ''),
  ('pexels-14839095', 'とわ', 'dog', 'ウェルシュ・コーギー'),
  ('pexels-7504007', 'おもち', 'cat', ''),
  ('pexels-34490255', 'しろ', 'dog', 'チワワ'),
  ('pexels-35274027', 'りん', 'cat', ''),
  ('pexels-35058642', 'ノア', 'dog', 'ロットワイラー'),
  ('pexels-14639088', 'ひなた', 'cat', 'メインクーン'),
  ('pexels-40070578', 'ポテト', 'dog', ''),
  ('pexels-29773501', 'ゆず', 'cat', ''),
  ('pexels-34658892', 'てん', 'dog', ''),
  ('pexels-39311622', 'あんず', 'cat', ''),
  ('pexels-6234629', 'こたろう', 'dog', 'ラフ・コリー'),
  ('pexels-28448365', 'こてつ', 'cat', 'ブリティッシュショートヘア'),
  ('pexels-23542061', 'はち', 'dog', 'ミニチュア・シュナウザー'),
  ('pexels-29404389', 'ふく', 'cat', ''),
  ('pexels-32739920', 'ももすけ', 'dog', ''),
  ('pexels-33964969', 'あお', 'cat', ''),
  ('pexels-16738458', 'バロン', 'dog', 'ラブラドール・レトリーバー'),
  ('pexels-16781395', 'ちびた', 'cat', ''),
  ('pexels-36581981', 'きなこ丸', 'dog', 'ジャーマン・シェパード'),
  ('pexels-9630275', 'いちご', 'cat', 'ペルシャ'),
  ('pexels-7534057', 'らい', 'dog', 'ポメラニアン'),
  ('pexels-33373209', 'うに', 'cat', 'ベンガル'),
  ('pexels-3361723', 'さんぽ', 'dog', ''),
  ('pexels-35694587', 'すみれ', 'cat', 'ラグドール');

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
   and s.pet_id=case item.species when 'dog' then '0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid else 'eaccee71-67b0-4222-ae16-ca404a568787'::uuid end;
 if n<>50 or p<>50 or ph<>50 or j<>50 then raise exception 'published source mapping changed: %,%,%,%',n,p,ph,j;end if;
 if (select count(*) from mefrion_private.public_posts where pet_id in ('0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,'eaccee71-67b0-4222-ae16-ca404a568787'::uuid) and state='published')<>50 then raise exception 'source account post count changed';end if;
 if exists(select 1 from mefrion_private.follows where pet_id in ('0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,'eaccee71-67b0-4222-ae16-ca404a568787'::uuid)) then raise exception 'collection followers require a separate migration plan';end if;
 if (select count(*) from mefrion_private.photos where pet_id in ('0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,'eaccee71-67b0-4222-ae16-ca404a568787'::uuid) and state='ready')<>50 then raise exception 'collection photo count changed';end if;
 if exists(select 1 from mefrion_private.seed_jobs where pet_id in ('0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,'eaccee71-67b0-4222-ae16-ca404a568787'::uuid) and state<>'published') then raise exception 'collection has another active or stopped job';end if;
end $$;

update stock_individual item set old_pet_id=s.pet_id,photo_id=photo.id,post_id=s.id,
 job_id=job.id,new_pet_id=gen_random_uuid()
from mefrion_private.photos photo
join mefrion_private.public_media media on media.source_id=photo.id and media.position=0
join mefrion_private.public_posts s on s.id=media.post_id
join mefrion_private.seed_jobs job on job.post_id=s.id and job.photos=array[photo.id]
where photo.title like item.asset_id || ' / %'
 and s.pet_id=case item.species when 'dog' then '0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid else 'eaccee71-67b0-4222-ae16-ca404a568787'::uuid end;

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
