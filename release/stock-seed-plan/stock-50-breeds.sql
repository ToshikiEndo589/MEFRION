-- Development-only guarded update for the approved 50-post run.
-- Labels come from saved Pexels alt text; unverified breeds remain unverified.
-- This changes account display names and per-post breed metadata only.
begin;
create temporary table stock50_labels(asset_id text primary key, breed_label text not null, species text not null) on commit drop;
insert into stock50_labels(asset_id,breed_label,species) values
  ('pexels-9000268', '柴犬（推定）', 'dog'),
  ('pexels-33238049', 'メインクーン（推定）', 'cat'),
  ('pexels-34584041', '犬種未確認', 'dog'),
  ('pexels-29102292', '猫種未確認', 'cat'),
  ('pexels-10802076', 'ダルメシアン（推定）', 'dog'),
  ('pexels-27505369', '猫種未確認', 'cat'),
  ('pexels-604680', 'チワワ（推定）', 'dog'),
  ('pexels-35708991', 'シャム（推定）', 'cat'),
  ('pexels-19216488', 'ウェルシュ・コーギー（推定）', 'dog'),
  ('pexels-34760125', '猫種未確認', 'cat'),
  ('pexels-10096129', 'ゴールデン・レトリーバー（推定）', 'dog'),
  ('pexels-33331606', '猫種未確認', 'cat'),
  ('pexels-32740130', 'ローデシアン・リッジバック（推定）', 'dog'),
  ('pexels-33146632', 'ラグドール（推定）', 'cat'),
  ('pexels-15175669', '犬種未確認', 'dog'),
  ('pexels-33495875', '猫種未確認', 'cat'),
  ('pexels-14530396', '柴犬（推定）', 'dog'),
  ('pexels-14304586', 'ペルシャ（推定）', 'cat'),
  ('pexels-27939375', 'ジャーマン・シェパード系ミックス（推定）', 'dog'),
  ('pexels-39024568', '猫種未確認', 'cat'),
  ('pexels-14148741', '犬種未確認', 'dog'),
  ('pexels-39563705', '猫種未確認', 'cat'),
  ('pexels-13026253', '犬種未確認', 'dog'),
  ('pexels-35279223', 'ブリティッシュショートヘア（推定）', 'cat'),
  ('pexels-16623448', '犬種未確認', 'dog'),
  ('pexels-38497229', '猫種未確認', 'cat'),
  ('pexels-14839095', 'ウェルシュ・コーギー（推定）', 'dog'),
  ('pexels-7504007', '猫種未確認', 'cat'),
  ('pexels-34490255', 'チワワ（推定）', 'dog'),
  ('pexels-35274027', '猫種未確認', 'cat'),
  ('pexels-35058642', 'ロットワイラー（推定）', 'dog'),
  ('pexels-14639088', 'メインクーン（推定）', 'cat'),
  ('pexels-40070578', '犬種未確認', 'dog'),
  ('pexels-29773501', '猫種未確認', 'cat'),
  ('pexels-34658892', '犬種未確認', 'dog'),
  ('pexels-39311622', '猫種未確認', 'cat'),
  ('pexels-6234629', 'ラフ・コリー（推定）', 'dog'),
  ('pexels-28448365', 'ブリティッシュショートヘア（推定）', 'cat'),
  ('pexels-23542061', 'ミニチュア・シュナウザー（推定）', 'dog'),
  ('pexels-29404389', '猫種未確認', 'cat'),
  ('pexels-32739920', '犬種未確認', 'dog'),
  ('pexels-33964969', '猫種未確認', 'cat'),
  ('pexels-16738458', 'ラブラドール・レトリーバー（推定）', 'dog'),
  ('pexels-16781395', '猫種未確認', 'cat'),
  ('pexels-36581981', 'ジャーマン・シェパード（推定）', 'dog'),
  ('pexels-9630275', 'ペルシャ（推定）', 'cat'),
  ('pexels-7534057', 'ポメラニアン（推定）', 'dog'),
  ('pexels-33373209', 'ベンガル（推定）', 'cat'),
  ('pexels-3361723', '犬種未確認', 'dog'),
  ('pexels-35694587', 'ラグドール（推定）', 'cat');
do $$
begin
 if (select count(*) from stock50_labels) <> 50 then raise exception 'Expected 50 labels'; end if;
 if (select count(*) from mefrion_private.pets p where
      (p.id='0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid and p.species='dog' and p.name in ('MEFRIONセレクト犬・検証','わんこ日和')) or
      (p.id='eaccee71-67b0-4222-ae16-ca404a568787'::uuid and p.species='cat' and p.name in ('MEFRIONセレクト猫・検証','にゃんこ日和'))) <> 2 then
   raise exception 'Managed collection accounts changed';
 end if;
 if (select count(*) from stock50_labels l
      join mefrion_private.photos ph on ph.title like l.asset_id || ' / %'
      join mefrion_private.public_media m on m.source_id=ph.id
      join mefrion_private.public_posts s on s.id=m.post_id
      join mefrion_private.pets p on p.id=s.pet_id and p.species=l.species
      where s.content_origin='managed_seed' and s.state='published'
        and s.pet_id in ('0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,'eaccee71-67b0-4222-ae16-ca404a568787'::uuid)) <> 50 then
   raise exception 'Expected 50 matching published photos';
 end if;
end $$;
update mefrion_private.pets set name='わんこ日和',breed='さまざまな犬種'
 where id='0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid;
update mefrion_private.pets set name='にゃんこ日和',breed='さまざまな猫種'
 where id='eaccee71-67b0-4222-ae16-ca404a568787'::uuid;
update mefrion_private.public_posts s set breed_label=l.breed_label
 from stock50_labels l
 join mefrion_private.photos ph on ph.title like l.asset_id || ' / %'
 join mefrion_private.public_media m on m.source_id=ph.id
 where s.id=m.post_id and s.content_origin='managed_seed' and s.state='published'
   and s.pet_id in ('0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,'eaccee71-67b0-4222-ae16-ca404a568787'::uuid);
do $$
begin
 if (select count(*) from mefrion_private.public_posts s
     where s.pet_id in ('0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,'eaccee71-67b0-4222-ae16-ca404a568787'::uuid)
       and s.state='published' and s.breed_label is not null) <> 50 then
   raise exception 'Not all 50 posts were labelled';
 end if;
end $$;
insert into mefrion_private.audit(pet_id,action) values
 ('0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,'seed.collection_name_and_breed_labels'),
 ('eaccee71-67b0-4222-ae16-ca404a568787'::uuid,'seed.collection_name_and_breed_labels');
commit;
select p.name,p.species,count(*) as labelled_posts from mefrion_private.pets p
 join mefrion_private.public_posts s on s.pet_id=p.id and s.state='published' and s.breed_label is not null
 where p.id in ('0a7a7290-f5d9-4260-b020-2f27f3f9f320'::uuid,'eaccee71-67b0-4222-ae16-ca404a568787'::uuid)
 group by p.name,p.species order by p.species;
