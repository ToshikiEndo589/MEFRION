begin;
create or replace function public.mefrion_request_publication(p_pet uuid,p_photos uuid[],p_body text,p_kind text,p_request_key uuid,p_explicit boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare item mefrion_private.public_posts;v_photo_id uuid;v_version integer;v_index integer:=0;media_id uuid;v_purpose text;v_kind text;
begin
 perform mefrion_private.require_registered();
 if p_explicit is distinct from true then raise exception 'explicit_publication_required';end if;
 if p_request_key is null or p_body is null or length(p_body)>500 or p_kind not in ('post','share') or p_photos is null or cardinality(p_photos) not between 1 and 10 or (p_kind='share' and cardinality(p_photos)<>2) or cardinality(p_photos)<>(select count(distinct id) from unnest(p_photos) id) then raise exception 'publication_invalid';end if;
 perform 1 from mefrion_private.pets where id=p_pet and owner_id=auth.uid() for update;
 if not found then raise exception 'owner_required' using errcode='42501';end if;
 if not exists(select 1 from mefrion_private.public_profiles where pet_id=p_pet and enabled) then raise exception 'profile_private';end if;
 select * into item from mefrion_private.public_posts where actor_id=auth.uid() and request_key=p_request_key;
 if found then
  if item.pet_id<>p_pet or item.body<>p_body or item.kind<>p_kind or (select array_agg(source_id order by position) from mefrion_private.public_media where post_id=item.id) is distinct from p_photos then raise exception 'idempotency_conflict';end if;
  return jsonb_build_object('id',item.id,'state',item.state);
 end if;
 v_purpose:=case when p_kind='post' then 'sns' else 'external_share' end;
 insert into mefrion_private.public_posts(pet_id,actor_id,request_key,body,kind) values(p_pet,auth.uid(),p_request_key,p_body,p_kind) returning * into item;
 foreach v_photo_id in array p_photos loop
  select c.version,p.media_kind into v_version,v_kind from mefrion_private.photos p join mefrion_private.consents c on c.photo_id=p.id
  where p.id=v_photo_id and p.pet_id=p_pet and p.state='ready' and c.purpose=v_purpose and c.allowed for update of p,c;
  if not found or (p_kind='share' and v_kind='video') then raise exception 'provider_consent_required' using errcode='42501';end if;
  media_id:=gen_random_uuid();
  insert into mefrion_private.public_media(id,post_id,source_id,consent_version,position,object_path)
  values(media_id,item.id,v_photo_id,v_version,v_index,media_id::text||case when v_kind='video' then '.mp4' else '.jpg' end);
  v_index:=v_index+1;
 end loop;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'publication.request');
 return jsonb_build_object('id',item.id,'state',item.state);
end $$;

commit;
