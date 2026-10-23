"""Prepare rollback-only assertions for the exact reserved development Pet."""
import json
from p1_test_support import ROOT
people=json.loads((ROOT/'.local/supabase-test-identities.json').read_text());owner=next(p['id'] for p in people if p['role']=='owner');family=next(p['id'] for p in people if p['role']=='family');pet=json.loads((ROOT/'.local/supabase-test-sessions.json').read_text())['pet_id']
sql="""begin;
do $test$
#variable_conflict use_variable
declare owner_id uuid:='OWNER';family_id uuid:='FAMILY';pet_id uuid:='PET';photo_id uuid:=gen_random_uuid();rows jsonb;digest text;
begin
 if not exists(select 1 from auth.users where id=owner_id and raw_user_meta_data->>'test_only'='true' and email like 'mefrion-test-%@example.invalid') or not exists(select 1 from auth.users where id=family_id and raw_user_meta_data->>'test_only'='true' and email like 'mefrion-test-%@example.invalid') or not exists(select 1 from mefrion_private.pets where id=pet_id and pets.owner_id=owner_id and name='E2E合成試験') then raise exception 'reserved_fixture_only';end if;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated','is_anonymous',false)::text,true);
 insert into mefrion_private.members(pet_id,user_id,active) values(pet_id,family_id,true) on conflict on constraint members_pkey do update set active=true;
 insert into mefrion_private.photos(id,pet_id,provider_id,object_path,request_key,title,state,ready_at) values(photo_id,pet_id,family_id,'rollback-notification-fixture-'||photo_id,gen_random_uuid(),'Rollback-only notification metadata; no photo file','ready',now()-interval '1 day');
 perform public.mefrion_pet_notifications(pet_id,'batched',false,null);
 update mefrion_private.pet_notification_settings s set changed_at=now()-interval '2 days' where s.pet_id=pet_id and user_id=owner_id;
 rows:=public.mefrion_family_notifications();digest:=pet_id::text||':'||((now()-interval '1 day') at time zone 'Asia/Tokyo')::date::text;
 if not exists(select 1 from jsonb_array_elements(rows) r where r->>'id'=digest and r->>'kind'='family_digest' and (r->>'count')::int>=1) then raise exception 'daily_digest_missing';end if;
 perform public.mefrion_pet_notifications(pet_id,'batched',false,now()+interval '1 day');
 if exists(select 1 from jsonb_array_elements(public.mefrion_family_notifications()) r where r->>'pet_id'=pet_id::text) then raise exception 'paused_digest_visible';end if;
 perform public.mefrion_pet_notifications(pet_id,'off',false,null);
 if exists(select 1 from jsonb_array_elements(public.mefrion_family_notifications()) r where r->>'pet_id'=pet_id::text) then raise exception 'disabled_digest_visible';end if;
 perform public.mefrion_pet_notifications(pet_id,'immediate',false,null);
 update mefrion_private.pet_notification_settings s set changed_at=now()-interval '2 days' where s.pet_id=pet_id and user_id=owner_id;
 if not exists(select 1 from jsonb_array_elements(public.mefrion_family_notifications()) r where r->>'id'=photo_id::text) then raise exception 'immediate_missing';end if;
 update mefrion_private.photos set state='deleted' where id=photo_id;
 if exists(select 1 from jsonb_array_elements(public.mefrion_family_notifications()) r where r->>'id'=photo_id::text) then raise exception 'deleted_photo_notification_visible';end if;
 perform set_config('request.jwt.claim.sub',family_id::text,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',family_id,'role','authenticated','is_anonymous',false)::text,true);
 perform public.mefrion_pet_notifications(pet_id,'batched',false,null);
 update mefrion_private.members m set active=false where m.pet_id=pet_id and user_id=family_id;
 if exists(select 1 from jsonb_array_elements(public.mefrion_family_notifications()) r where r->>'pet_id'=pet_id::text) then raise exception 'exited_family_notification_visible';end if;
end $test$;
rollback;
select 'PASS: prior-day digest, pause, off, immediate, deletion, family exit; all fixture changes rolled back' as result;
"""
for key,value in [('OWNER',owner),('FAMILY',family),('PET',pet)]:sql=sql.replace(key,value)
p=ROOT/'.local/p1-notification-clock-test.sql';p.write_text(sql);p.chmod(0o600);print('Rollback-only reserved fixture assertions prepared; identities not printed.')
