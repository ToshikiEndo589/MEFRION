begin;
-- Tombstone before eventual Auth/blob cleanup. This table is also the restore
-- ledger: restoring an older backup must reapply retirement before serving it.
create table mefrion_private.account_retirements (
 user_id uuid primary key references auth.users(id), request_key uuid not null unique,
 state text not null default 'pending' check(state in ('pending','done')),
 paths jsonb not null, created_at timestamptz not null default now(), completed_at timestamptz
);
alter table mefrion_private.account_retirements enable row level security;
revoke all on mefrion_private.account_retirements from public,anon,authenticated;
create or replace function mefrion_private.require_registered() returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or coalesce(auth.jwt()->>'is_anonymous','false')='true' then raise exception 'registration_required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 if exists(select 1 from mefrion_private.account_retirements where user_id=auth.uid()) then raise exception 'account_retired' using errcode='42501';end if;
end $$;
create or replace function public.mefrion_family_access(p_pet uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce(auth.jwt()->>'is_anonymous','false')<>'true'
 and not exists(select 1 from mefrion_private.account_retirements where user_id=auth.uid())
 and exists(select 1 from mefrion_private.pets p where p.id=p_pet
 and not exists(select 1 from mefrion_private.account_retirements where user_id=p.owner_id)
 and (p.owner_id=auth.uid() or exists(select 1 from mefrion_private.members m where m.pet_id=p.id and m.user_id=auth.uid() and m.active)))
$$;
create or replace function mefrion_private.social_actor_visible(p_actor uuid,p_other uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select not exists(select 1 from mefrion_private.account_retirements where user_id in (p_actor,p_other))
 and not exists(select 1 from mefrion_private.public_account_states where user_id=p_other and suspended)
 and not exists(select 1 from mefrion_private.social_blocks where (actor_id=p_actor and target_id=p_other) or (actor_id=p_other and target_id=p_actor))
$$;
-- Serialize private writes with account retirement, including RPCs without an
-- explicit registration helper. Service cleanup remains separately authorized.
create function mefrion_private.retirement_write_gate() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if auth.role()='authenticated' then perform mefrion_private.require_registered();end if;
 return new;
end $$;
revoke all on function mefrion_private.retirement_write_gate() from public,anon,authenticated;
create trigger mefrion_retirement_pets before insert or update on mefrion_private.pets for each row execute function mefrion_private.retirement_write_gate();
create trigger mefrion_retirement_photos before insert or update on mefrion_private.photos for each row execute function mefrion_private.retirement_write_gate();
create trigger mefrion_retirement_members before insert or update on mefrion_private.members for each row execute function mefrion_private.retirement_write_gate();
create trigger mefrion_retirement_invites before insert or update on mefrion_private.invites for each row execute function mefrion_private.retirement_write_gate();
create trigger mefrion_retirement_consents before insert or update on mefrion_private.consents for each row execute function mefrion_private.retirement_write_gate();
create or replace function public.mefrion_request_retirement(p_request_key uuid,p_explicit boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_photo uuid;v_post uuid;v_paths jsonb;v_old mefrion_private.account_retirements;
begin
 if v_user is null or coalesce(auth.jwt()->>'is_anonymous','false')='true' or p_request_key is null or p_explicit is distinct from true then raise exception 'explicit_retirement_required' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text,0));
 select * into v_old from mefrion_private.account_retirements where user_id=v_user;
 if found then
  if v_old.request_key<>p_request_key then raise exception 'retirement_already_requested';end if;
  return jsonb_build_object('accepted',true,'state',v_old.state);
 end if;
 -- A new sign-in is required immediately before requesting irreversible cleanup.
 if coalesce((auth.jwt()->>'iat')::bigint,0)<extract(epoch from now())-300 then raise exception 'recent_login_required' using errcode='42501';end if;
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
 update mefrion_private.pets set name='削除済み',breed='',introduction='' where owner_id=v_user;
 update mefrion_private.photos set title='',captured=null where provider_id=v_user or pet_id in(select id from mefrion_private.pets where owner_id=v_user);
 update mefrion_private.public_posts set body='' where actor_id=v_user or pet_id in(select id from mefrion_private.pets where owner_id=v_user);
 insert into mefrion_private.account_retirements(user_id,request_key,paths) values(v_user,p_request_key,v_paths);
 insert into mefrion_private.audit(actor_id,action) values(v_user,'account.retirement.request');
 return jsonb_build_object('accepted',true,'state','pending');
end $$;
create or replace function public.mefrion_retirement_batch() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'service_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'paths',paths)),'[]'::jsonb) from(select user_id,paths from mefrion_private.account_retirements where state='pending' order by created_at limit 10) q);
end $$;
create or replace function public.mefrion_retirement_ack(p_user uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'service_required' using errcode='42501';end if;
 -- Only after the service worker confirms storage absence and Auth erasure.
 update mefrion_private.account_retirements set state='done',completed_at=now() where user_id=p_user;
 return found;
end $$;
revoke execute on function public.mefrion_request_retirement(uuid,boolean) from public,anon;
grant execute on function public.mefrion_request_retirement(uuid,boolean) to authenticated;
revoke execute on function public.mefrion_retirement_batch(),public.mefrion_retirement_ack(uuid) from public,anon,authenticated;
grant execute on function public.mefrion_retirement_batch(),public.mefrion_retirement_ack(uuid) to service_role;
commit;
