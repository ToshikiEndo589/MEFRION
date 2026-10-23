begin;
create table mefrion_private.seed_rate(actor_id uuid primary key references auth.users(id),window_at timestamptz not null,requests integer not null);
alter table mefrion_private.seed_rate enable row level security;revoke all on mefrion_private.seed_rate from public,anon,authenticated;
create or replace function mefrion_private.require_seed(p_task text) returns void language plpgsql security definer set search_path='' as $$
declare n integer;bucket timestamptz:=date_trunc('minute',now());
begin
 perform mefrion_private.require_registered();if not mefrion_private.seed_access(p_task) then raise exception 'seed_role_and_mfa_required' using errcode='42501';end if;
 perform 1 from mefrion_private.operators where user_id=auth.uid() and active and expires_at>now() and (role='admin' or (p_task='edit' and role='editor') or (p_task='approve' and role='approver') or (p_task='view' and role in ('editor','approver'))) for share;
 if not found then raise exception 'seed_role_and_mfa_required' using errcode='42501';end if;
 if p_task<>'view' then
  insert into mefrion_private.seed_rate values(auth.uid(),bucket,1) on conflict(actor_id) do update set window_at=excluded.window_at,requests=case when seed_rate.window_at=excluded.window_at then seed_rate.requests+1 else 1 end returning requests into n;
  if n>120 then raise exception 'seed_rate_limit';end if;
 end if;
end $$;
create table mefrion_private.seed_rights_history(id bigint generated always as identity primary key,photo_id uuid not null references mefrion_private.photos(id),actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default now(),operation text not null,snapshot jsonb not null);
alter table mefrion_private.seed_rights_history enable row level security;revoke all on mefrion_private.seed_rights_history from public,anon,authenticated;
insert into mefrion_private.seed_rights_history(photo_id,actor_id,recorded_at,operation,snapshot) select photo_id,checked_by,checked_at,'baseline-before-history',to_jsonb(r) from mefrion_private.managed_photo_rights r;
create function mefrion_private.record_seed_rights() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into mefrion_private.seed_rights_history(photo_id,actor_id,operation,snapshot) values(new.photo_id,new.checked_by,lower(tg_op),to_jsonb(new));return new;
end $$;
create trigger seed_rights_history after insert or update on mefrion_private.managed_photo_rights for each row execute function mefrion_private.record_seed_rights();
create function public.mefrion_seed_permissions() returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin
 perform mefrion_private.require_seed('view');return jsonb_build_object('edit',mefrion_private.seed_access('edit'),'approve',mefrion_private.seed_access('approve'),'publish',mefrion_private.seed_access('publish'),'schedule',mefrion_private.seed_access('schedule'),'stop',mefrion_private.seed_access('stop'));
end $$;
create function public.mefrion_seed_rights_history(p_pet uuid) returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin
 perform mefrion_private.require_seed('view');if not exists(select 1 from mefrion_private.managed_pets where pet_id=p_pet) then raise exception 'managed_pet_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('photo_id',h.photo_id,'actor_id',h.actor_id,'recorded_at',h.recorded_at,'operation',h.operation,'rights',h.snapshot) order by h.id desc),'[]') from (select h.* from mefrion_private.seed_rights_history h join mefrion_private.photos p on p.id=h.photo_id where p.pet_id=p_pet order by h.id desc limit 100) h);
end $$;
revoke execute on function mefrion_private.record_seed_rights() from public,anon,authenticated;
revoke execute on function public.mefrion_seed_permissions(),public.mefrion_seed_rights_history(uuid) from public,anon;grant execute on function public.mefrion_seed_permissions(),public.mefrion_seed_rights_history(uuid) to authenticated;
commit;
