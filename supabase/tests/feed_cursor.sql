-- Actual social_page projection: ties must survive successive one-item pages.
begin;
set local session_replication_role = replica;
do $$
declare owner uuid:=gen_random_uuid();pet uuid:=gen_random_uuid();photo uuid;post uuid;
 stamp timestamptz:=now();ids uuid[]:='{}';seen uuid[]:='{}';page jsonb;cursor_id uuid;cursor_at timestamptz;i integer;
begin
 insert into auth.users(id,aud,role,email) values(owner,'authenticated','authenticated',owner||'@cursor-test.invalid');
 insert into mefrion_private.pets(id,owner_id,name,species) values(pet,owner,'cursor-fixture','dog');
 insert into mefrion_private.public_profiles(pet_id,enabled) values(pet,true);
 for i in 1..4 loop
  photo:=gen_random_uuid();post:=gen_random_uuid();
  insert into mefrion_private.photos(id,pet_id,provider_id,object_path,request_key,state) values(photo,pet,owner,photo||'.jpg',gen_random_uuid(),'ready');
  insert into mefrion_private.consents(photo_id,purpose,allowed,version) values(photo,'sns',true,1);
  insert into mefrion_private.public_posts(id,pet_id,actor_id,request_key,kind,state,published_at)
   values(post,pet,owner,gen_random_uuid(),'post',case when i=4 then 'stopped' else 'published' end,stamp-case when i=3 then interval '1 second' else interval '0 seconds' end);
  insert into mefrion_private.public_media(post_id,source_id,consent_version,position,object_path) values(post,photo,1,0,post||'.jpg');
  if i<4 then ids:=array_append(ids,post);end if;
 end loop;
 for i in 1..4 loop
  page:=mefrion_private.social_page(1,'all','cursor-fixture',cursor_at,cursor_id,'all');
  if i=4 then
   if jsonb_array_length(page)<>0 then raise exception 'cursor exposed stopped post or duplicated row';end if;
  else
   if jsonb_array_length(page)<>1 then raise exception 'cursor skipped a tied timestamp';end if;
   cursor_id:=(page->0->>'id')::uuid;cursor_at:=(page->0->>'published_at')::timestamptz;
   if cursor_id=any(seen) then raise exception 'cursor repeated row';end if;
   seen:=array_append(seen,cursor_id);
  end if;
 end loop;
 if not seen @> ids or cardinality(seen)<>3 then raise exception 'cursor lost rows';end if;
end $$;
rollback;
