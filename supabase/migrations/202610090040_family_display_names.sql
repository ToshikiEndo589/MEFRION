begin;
create table mefrion_private.family_display_names(pet_id uuid not null references mefrion_private.pets(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,name text not null check(length(name) between 1 and 40),primary key(pet_id,user_id));
alter table mefrion_private.family_display_names enable row level security;
revoke all on mefrion_private.family_display_names from public,anon,authenticated;
create function mefrion_private.family_display_name(p_pet uuid,p_user uuid) returns text language sql stable security definer set search_path='' as $$
 select coalesce((select n.name from mefrion_private.family_display_names n where n.pet_id=p_pet and n.user_id=p_user and not exists(select 1 from mefrion_private.account_retirements r where r.user_id=p_user)),case when p_user=auth.uid() then 'あなた' else '家族メンバー' end)
$$;
revoke execute on function mefrion_private.family_display_name(uuid,uuid) from public,anon,authenticated;
create function public.mefrion_set_family_name(p_pet uuid,p_name text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();perform 1 from mefrion_private.pets where id=p_pet for share;
 if not public.mefrion_family_access(p_pet) then raise exception 'family_permission_required' using errcode='42501';end if;
 if p_name is null or length(btrim(p_name))>40 then raise exception 'family_name_invalid';end if;
 if btrim(p_name)='' then delete from mefrion_private.family_display_names where pet_id=p_pet and user_id=auth.uid();
 else insert into mefrion_private.family_display_names values(p_pet,auth.uid(),btrim(p_name)) on conflict(pet_id,user_id) do update set name=excluded.name;end if;return true;
end $$;
revoke execute on function public.mefrion_set_family_name(uuid,text) from public,anon;
grant execute on function public.mefrion_set_family_name(uuid,text) to authenticated;
create or replace function public.mefrion_members(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'role',role,'me',id=auth.uid(),'display_name',mefrion_private.family_display_name(p_pet,id))),'[]') from (select p.owner_id id,'owner'::text role from mefrion_private.pets p where p.id=p_pet union all select m.user_id,'family' from mefrion_private.members m where m.pet_id=p_pet and m.active) u);
end $$;
create or replace function public.mefrion_album(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'path',object_path,'captured',captured,'title',title,'mine',provider_id=auth.uid(),'event_kind',event_kind,'note',note,'provider_name',mefrion_private.family_display_name(p_pet,provider_id)) order by captured desc nulls last,created_at desc,id),'[]') from mefrion_private.photos where pet_id=p_pet and state='ready');
end $$;
create or replace function public.mefrion_family_activity(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id::text,'action',action,'mine',actor_id=auth.uid(),'created_at',created_at,'actor_name',mefrion_private.family_display_name(p_pet,actor_id)) order by created_at desc,id desc),'[]') from (select * from mefrion_private.audit where pet_id=p_pet and action in ('photo.create','photo.finish','photo.delete','pet.update','invite.accept','member.remove','card.create') order by created_at desc,id desc limit 50) a);
end $$;
commit;
