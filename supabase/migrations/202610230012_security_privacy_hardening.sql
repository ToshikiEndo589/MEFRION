-- Verified authorization/privacy findings from the 2026-10-23 penetration tests.
-- No raw IP addresses are retained. Existing app RPC signatures remain compatible.
begin;
select vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'mefrion_reference_quota_salt','Daily guest quota HMAC; never returned to clients')
where not exists(select 1 from vault.secrets where name='mefrion_reference_quota_salt');

create function mefrion_private.reference_guest_actor() returns text
language plpgsql stable security definer set search_path='' as $$
declare headers jsonb;parts text[];address inet;network text;salt text;
begin
 headers:=nullif(current_setting('request.headers',true),'')::jsonb;
 -- The API ingress supplies CF-Connecting-IP. A caller-supplied XFF prefix
 -- cannot replace it. The last forwarded hop is the fallback at other ingress.
 parts:=regexp_split_to_array(coalesce(headers->>'x-forwarded-for',''),'\s*,\s*');
 begin
  address:=coalesce(nullif(headers->>'cf-connecting-ip',''),nullif(parts[array_upper(parts,1)],''))::inet;
 exception when invalid_text_representation then
  raise exception 'reference_identity_required' using errcode='42501';
 end;
 if address is null then raise exception 'reference_identity_required' using errcode='42501';end if;
 network:=case when family(address)=6 then set_masklen(address,64)::cidr::text else host(address) end;
 select decrypted_secret into salt from vault.decrypted_secrets where name='mefrion_reference_quota_salt';
 if salt is null then raise exception 'reference_identity_unavailable' using errcode='42501';end if;
 return 'network:'||encode(extensions.hmac((now() at time zone 'Asia/Tokyo')::date::text||':'||network,salt,'sha256'),'hex');
end $$;
revoke all on function mefrion_private.reference_guest_actor() from public,anon,authenticated,service_role;


CREATE OR REPLACE FUNCTION public.mefrion_reference_search(p_species text, p_query text, p_fingerprint text, p_mean real, p_revision integer, p_consent boolean, p_guest uuid, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
AS $function$
declare
 q extensions.vector(768); fp bit(144); actor_id text; today date; used integer; cap integer;
 chosen text[]='{}'; prints bit(144)[]='{}'; means real[]='{}'; vectors extensions.vector[]='{}';
 row_data record; cached record; duplicate boolean; i integer;
begin
 if p_consent is distinct from true or p_species not in ('dog','cat') or p_species is null or p_revision is distinct from 2 or p_request is null or p_fingerprint is null or p_fingerprint !~ '^[01]{144}$' or p_mean is null or p_mean not between 0 and 255 then raise exception 'invalid_reference_query';end if;
 if p_query is null or length(p_query)>32000 then raise exception 'invalid_reference_query';end if;
 q=p_query::extensions.vector(768);fp=p_fingerprint::bit(144);
 if q is null then raise exception 'invalid_reference_query';end if;
 if auth.uid() is null then
   if p_guest is null then raise exception 'invalid_reference_guest';end if;
   actor_id=case when auth.role()='service_role' then 'guest:'||p_guest::text else mefrion_private.reference_guest_actor() end;today=(now() at time zone 'Asia/Tokyo')::date;cap=10;
 else actor_id='user:'||auth.uid()::text;today=(now() at time zone 'Asia/Tokyo')::date;cap=50;end if;
 -- Same request is replayable for 10 minutes without charging another search.
 select * into cached from public.mefrion_reference_retries where id=p_request and actor=actor_id and species=p_species and expires>now();
 if found then return public.mefrion_reference_lookup(cached.candidates);end if;
 -- Rate counter row is locked to avoid concurrent requests exceeding the cap.
 insert into public.mefrion_reference_usage(actor,day) values(actor_id,today) on conflict do nothing;
 select count into used from public.mefrion_reference_usage where actor=actor_id and day=today for update;
 select * into cached from public.mefrion_reference_retries where id=p_request and actor=actor_id and species=p_species and expires>now();
 if found then return public.mefrion_reference_lookup(cached.candidates);end if;
 if coalesce(auth.role(),'anon')<>'service_role' and used>=cap then raise exception 'reference_search_limit';end if;
 for row_data in
   select a.* from public.mefrion_reference_assets a
   where a.active and a.withdrawn_at is null and a.species=p_species
   order by a.embedding operator(extensions.<->) q limit 100
 loop
   if (row_data.embedding operator(extensions.<->) q)>1.1 or (row_data.embedding operator(extensions.<->) q)<=0.08 then continue;end if;
   if abs(row_data.mean-p_mean)<=4 and bit_count(row_data.fingerprint # fp)<=12 then continue;end if;
   duplicate=false;
   for i in 1..coalesce(array_length(chosen,1),0) loop
     if (abs(means[i]-row_data.mean)<=4 and bit_count(prints[i] # row_data.fingerprint)<=12) or (vectors[i] operator(extensions.<->) row_data.embedding)<=0.08 then duplicate=true;exit;end if;
   end loop;
   if duplicate then continue;end if;
   chosen=array_append(chosen,row_data.id);prints=array_append(prints,row_data.fingerprint);means=array_append(means,row_data.mean);vectors=array_append(vectors,row_data.embedding);
   if cardinality(chosen)=3 then exit;end if;
 end loop;
 update public.mefrion_reference_usage set count=count+1 where actor=actor_id and day=today;
 insert into public.mefrion_reference_retries values(p_request,actor_id,p_species,chosen,now()+interval '10 minutes');
 delete from public.mefrion_reference_retries where expires<=now();
 delete from public.mefrion_reference_usage where day<today-2;
 return public.mefrion_reference_lookup(chosen);
end;$function$
;

CREATE OR REPLACE FUNCTION public.mefrion_reference_search_v2(p_species text, p_query text, p_color text, p_legacy text, p_fingerprint text, p_mean real, p_algorithm text, p_consent boolean, p_guest uuid, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '10s'
 SET "hnsw.ef_search" TO '240'
AS $function$
declare
 q extensions.vector(384); c extensions.vector(64); legacy extensions.vector(768); fp bit(144);
 actor_id text; today date; used integer; cap integer; chosen text[]='{}';
 prints bit(144)[]='{}'; means real[]='{}'; vectors extensions.vector[]='{}'; credits text[]='{}';
 row_data record; cached record; duplicate boolean; i integer;
begin
 if p_consent is distinct from true or p_species is null or p_species not in ('dog','cat') or p_algorithm is distinct from 'dinov2-small-subject-v1' or p_request is null or p_fingerprint is null or p_fingerprint !~ '^[01]{144}$' or p_mean is null or not(p_mean between 0 and 255) then raise exception 'invalid_reference_query';end if;
 if p_query is null or length(p_query)>16000 or p_color is null or length(p_color)>4096 or p_legacy is null or length(p_legacy)>32000 then raise exception 'invalid_reference_query';end if;
 q=p_query::extensions.vector(384);c=p_color::extensions.vector(64);legacy=p_legacy::extensions.vector(768);fp=p_fingerprint::bit(144);
 if q is null or c is null or legacy is null or extensions.vector_norm(q) not between 0.98 and 1.02 or extensions.vector_norm(c) not between 0.98 and 1.02 then raise exception 'invalid_reference_query';end if;
 if auth.uid() is null then
  if p_guest is null then raise exception 'invalid_reference_guest';end if;
  actor_id=case when auth.role()='service_role' then 'guest:'||p_guest::text else mefrion_private.reference_guest_actor() end;cap=10;
 else actor_id='user:'||auth.uid()::text;cap=50;end if;
 today=(now() at time zone 'Asia/Tokyo')::date;
 select * into cached from public.mefrion_resemblance_retries where id=p_request and actor=actor_id and species=p_species and expires>now();
 if found then return public.mefrion_reference_lookup(cached.candidates);end if;
 insert into public.mefrion_reference_usage(actor,day) values(actor_id,today) on conflict do nothing;
 select count into used from public.mefrion_reference_usage where actor=actor_id and day=today for update;
 select * into cached from public.mefrion_resemblance_retries where id=p_request and actor=actor_id and species=p_species and expires>now();
 if found then return public.mefrion_reference_lookup(cached.candidates);end if;
 if coalesce(auth.role(),'anon')<>'service_role' and used>=cap then raise exception 'reference_search_limit';end if;
 for row_data in
  with nearest as materialized (
   select r.id,r.embedding operator(extensions.<=>) q as semantic,r.color operator(extensions.<=>) c as color_distance
   from public.mefrion_reference_resemblance r join public.mefrion_reference_assets a using(id)
   where a.active and a.withdrawn_at is null and a.species=p_species and r.species=p_species
   order by r.embedding operator(extensions.<=>) q limit 240
  )
  select a.*,n.semantic from nearest n join public.mefrion_reference_assets a using(id)
  where n.semantic<=0.5
  order by n.semantic+0.12*n.color_distance,a.id
 loop
  if row_data.credit=any(credits) or (row_data.embedding operator(extensions.<->) legacy)<=0.08 then continue;end if;
  if abs(row_data.mean-p_mean)<=4 and bit_count(row_data.fingerprint # fp)<=12 then continue;end if;
  duplicate=false;
  for i in 1..coalesce(array_length(chosen,1),0) loop
   if (abs(means[i]-row_data.mean)<=4 and bit_count(prints[i] # row_data.fingerprint)<=12) or (vectors[i] operator(extensions.<->) row_data.embedding)<=0.08 then duplicate=true;exit;end if;
  end loop;
  if duplicate then continue;end if;
  credits=array_append(credits,row_data.credit);chosen=array_append(chosen,row_data.id);prints=array_append(prints,row_data.fingerprint);means=array_append(means,row_data.mean);vectors=array_append(vectors,row_data.embedding);
  if cardinality(chosen)=3 then exit;end if;
 end loop;
 update public.mefrion_reference_usage set count=count+1 where actor=actor_id and day=today;
 insert into public.mefrion_resemblance_retries values(p_request,actor_id,p_species,chosen,now()+interval '10 minutes');
 delete from public.mefrion_resemblance_retries where expires<=now();
 delete from public.mefrion_reference_usage where day<today-2;
 return public.mefrion_reference_lookup(chosen);
end;$function$
;

CREATE OR REPLACE FUNCTION public.mefrion_social_connections(p_kind text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 40)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
  perform mefrion_private.require_registered();
  if p_kind not in ('following','followers') or p_offset is null or p_offset < 0 or p_offset > 10000
     or p_limit is null or p_limit < 1 or p_limit > 50 then
    raise exception 'connections_invalid';
  end if;
  if p_kind = 'following' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', f.pet_id::text, 'name', pet.name, 'species', pet.species,
      'breed', case when 'breed'=any(pet.public_fields) then pet.breed else '' end,
      'profile_pet_id', pet.id, 'followed_pet_name', null
    ) order by f.created_at desc, f.pet_id desc),'[]'::jsonb) into result
    from (select f.* from mefrion_private.follows f
      join mefrion_private.pets pet on pet.id=f.pet_id
      join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled
      where f.actor_id=auth.uid()
        and mefrion_private.social_actor_visible(auth.uid(),pet.owner_id)
      order by f.created_at desc,f.pet_id desc limit p_limit offset p_offset) f
    join mefrion_private.pets pet on pet.id=f.pet_id;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', encode(extensions.digest(f.actor_id::text||':'||f.pet_id::text,'sha256'),'hex'),
      'name', coalesce(nullif(public_pet.name,''),nullif(identity.name,''),'フォロワー'),
      'species', public_pet.species,
      'breed', case when 'breed'=any(public_pet.public_fields) then public_pet.breed else '' end,
      'profile_pet_id', public_pet.id, 'followed_pet_name', followed.name
    ) order by f.created_at desc,f.pet_id desc,f.actor_id desc),'[]'::jsonb) into result
    from (select f.* from mefrion_private.follows f
      join mefrion_private.pets own_pet on own_pet.id=f.pet_id
      where own_pet.owner_id=auth.uid()
        and mefrion_private.social_actor_visible(auth.uid(),f.actor_id)
      order by f.created_at desc,f.pet_id desc,f.actor_id desc limit p_limit offset p_offset) f
    join mefrion_private.pets followed on followed.id=f.pet_id
    left join mefrion_private.social_identities identity on identity.user_id=f.actor_id
    left join lateral (
      select pet.id,pet.name,pet.species,pet.breed,pet.public_fields
      from mefrion_private.pets pet
      join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled
      where pet.owner_id=f.actor_id and mefrion_private.managed_public_ready(pet.id)
      order by pet.id limit 1
    ) public_pet on true;
  end if;
  return result;
end $function$
;

CREATE OR REPLACE FUNCTION mefrion_private.request_retirement_impl(p_request_key uuid, p_explicit boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid:=auth.uid();v_photo uuid;v_post uuid;v_paths jsonb;v_old mefrion_private.account_retirements;
begin
 if v_user is null or coalesce(auth.jwt()->>'is_anonymous','false')='true' or p_request_key is null or p_explicit is distinct from true then raise exception 'explicit_retirement_required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text,0));
 select * into v_old from mefrion_private.account_retirements where user_id=v_user;
 if found then
  if v_old.request_key<>p_request_key then raise exception 'retirement_already_requested';end if;
  return jsonb_build_object('accepted',true,'state',v_old.state);
 end if;
 -- The public RPC checks the current identity and explicit confirmation.

 perform 1 from auth.users where id=v_user for update;
 perform 1 from mefrion_private.pets where owner_id=v_user for update;
 select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket,'path',path)),'[]'::jsonb) into v_paths from (
 select 'family-originals'::text bucket,p.object_path path from mefrion_private.photos p join mefrion_private.pets pet on pet.id=p.pet_id where p.provider_id=v_user or pet.owner_id=v_user
 union select 'public-derived',m.object_path from mefrion_private.public_media m join mefrion_private.photos p on p.id=m.source_id join mefrion_private.pets pet on pet.id=p.pet_id where p.provider_id=v_user or pet.owner_id=v_user
 ) objects;
 for v_photo in select p.id from mefrion_private.photos p join mefrion_private.pets pet on pet.id=p.pet_id where p.provider_id=v_user or pet.owner_id=v_user loop perform public.mefrion_delete_photo(v_photo);end loop;
 for v_post in select s.id from mefrion_private.public_posts s join mefrion_private.pets p on p.id=s.pet_id where s.actor_id=v_user or p.owner_id=v_user loop perform mefrion_private.stop_publication(v_post);end loop;
 update mefrion_private.public_profiles set enabled=false where pet_id in(select id from mefrion_private.pets where owner_id=v_user);
 update mefrion_private.members set active=false where user_id=v_user or pet_id in(select id from mefrion_private.pets where owner_id=v_user);
 update mefrion_private.invites set state='revoked' where pet_id in(select id from mefrion_private.pets where owner_id=v_user);
 delete from mefrion_private.cards where pet_id in(select id from mefrion_private.pets where owner_id=v_user);
 update mefrion_private.social_comments set state='deleted',body='',speaker_name='削除済み' where actor_id=v_user;
 delete from mefrion_private.social_notifications where actor_id=v_user or recipient_id=v_user or pet_id in(select id from mefrion_private.pets where owner_id=v_user);
 delete from mefrion_private.reactions where actor_id=v_user;
 delete from mefrion_private.follows where actor_id=v_user;
 delete from mefrion_private.social_identities where user_id=v_user;
 update mefrion_private.operators set active=false where user_id=v_user;
 -- Erase free text and profile details as well as photo bytes. Keep only
 -- pseudonymous tombstones needed to prevent accidental resurrection.
 delete from mefrion_private.family_display_names where user_id=v_user or pet_id in(select id from mefrion_private.pets where owner_id=v_user);
 delete from mefrion_private.pet_events where actor_id=v_user or pet_id in(select id from mefrion_private.pets where owner_id=v_user);
 delete from mefrion_private.cards where actor_id=v_user;
 update mefrion_private.pets set details='{}'::jsonb,public_fields='{}'::text[] where owner_id=v_user;
 update mefrion_private.photos set note='',event_kind=null where provider_id=v_user or pet_id in(select id from mefrion_private.pets where owner_id=v_user);
 update mefrion_private.pets set name='削除済み',breed='',introduction='' where owner_id=v_user;
 update mefrion_private.photos set title='',captured=null where provider_id=v_user or pet_id in(select id from mefrion_private.pets where owner_id=v_user);
 update mefrion_private.public_posts set body='' where actor_id=v_user or pet_id in(select id from mefrion_private.pets where owner_id=v_user);
 insert into mefrion_private.account_retirements(user_id,request_key,paths) values(v_user,p_request_key,v_paths);
 insert into mefrion_private.audit(actor_id,action) values(v_user,'account.retirement.request');
 return jsonb_build_object('accepted',true,'state','pending');
end $function$
;


-- Backfill only accounts with an existing explicit retirement record.
delete from mefrion_private.family_display_names f where exists(select 1 from mefrion_private.account_retirements r where r.user_id=f.user_id) or exists(select 1 from mefrion_private.pets p join mefrion_private.account_retirements r on r.user_id=p.owner_id where p.id=f.pet_id);
delete from mefrion_private.pet_events e where exists(select 1 from mefrion_private.account_retirements r where r.user_id=e.actor_id) or exists(select 1 from mefrion_private.pets p join mefrion_private.account_retirements r on r.user_id=p.owner_id where p.id=e.pet_id);
delete from mefrion_private.cards c where exists(select 1 from mefrion_private.account_retirements r where r.user_id=c.actor_id);
update mefrion_private.pets p set details='{}'::jsonb,public_fields='{}'::text[] where exists(select 1 from mefrion_private.account_retirements r where r.user_id=p.owner_id);
update mefrion_private.photos p set note='',event_kind=null where exists(select 1 from mefrion_private.account_retirements r where r.user_id=p.provider_id) or exists(select 1 from mefrion_private.pets pet join mefrion_private.account_retirements r on r.user_id=pet.owner_id where pet.id=p.pet_id);
notify pgrst,'reload schema';
commit;
