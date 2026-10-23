begin;
create or replace function public.mefrion_twins_enroll(p_pet uuid,p_photo uuid,p_key uuid,p_explicit boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare t mefrion_private.twins_candidates;v integer;old_id uuid;new_id uuid:=gen_random_uuid();
begin
 perform mefrion_private.require_registered();
 if p_explicit is distinct from true or p_key is null then raise exception 'explicit_twins_enrollment_required';end if;
 perform 1 from mefrion_private.pets p join mefrion_private.public_profiles f on f.pet_id=p.id and f.enabled where p.id=p_pet and p.owner_id=auth.uid() for update of p;
 if not found then raise exception 'owned_public_pet_required' using errcode='42501';end if;
 select c.version into v from mefrion_private.photos photo join mefrion_private.consents c on c.photo_id=photo.id and c.purpose='twins' and c.allowed where photo.id=p_photo and photo.pet_id=p_pet and photo.state='ready' for share of photo,c;
 if not found then raise exception 'provider_twins_consent_required' using errcode='42501';end if;
 select * into t from mefrion_private.twins_candidates where owner_id=auth.uid() and request_key=p_key;
 if found then if t.pet_id<>p_pet or t.source_id<>p_photo or t.consent_version<>v then raise exception 'idempotency_conflict';end if;return jsonb_build_object('id',t.id,'state',t.state);end if;
 for old_id in select id from mefrion_private.twins_candidates where pet_id=p_pet and state<>'stopped' for update loop perform mefrion_private.stop_twins(old_id);end loop;
 insert into mefrion_private.twins_candidates(id,pet_id,source_id,owner_id,consent_version,request_key,object_path) values(new_id,p_pet,p_photo,auth.uid(),v,p_key,'twins-'||new_id::text||'.jpg');
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'twins.enroll');return jsonb_build_object('id',new_id,'state','pending');
end $$;
commit;
