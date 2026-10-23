begin;
alter table mefrion_private.photos add column ready_at timestamptz;
alter table mefrion_private.cards add column actor_id uuid references auth.users(id);
alter table mefrion_private.cards add column request_key uuid;
alter table mefrion_private.cards add column created_at timestamptz not null default now();
create unique index mefrion_card_request on mefrion_private.cards(actor_id,request_key);
create table mefrion_private.family_reads(pet_id uuid references mefrion_private.pets(id) on delete cascade,user_id uuid references auth.users(id),seen_at timestamptz not null default now(),primary key(pet_id,user_id));
alter table mefrion_private.family_reads enable row level security;
revoke all on mefrion_private.family_reads from public,anon,authenticated;
create function public.mefrion_save_card(p_pet uuid,p_first uuid,p_second uuid,p_layout jsonb,p_key uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare v mefrion_private.cards;k text;x numeric;
begin
 perform mefrion_private.require_registered();perform 1 from mefrion_private.pets where id=p_pet for share;
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 if p_key is null or p_first is null or p_second is null or p_first=p_second or p_layout is null or jsonb_typeof(p_layout)<>'object' or length(p_layout::text)>4000 or length(coalesce(p_layout->>'text',''))>200 then raise exception 'card_invalid';end if;
 if exists(select 1 from jsonb_object_keys(p_layout) t(key) where key not in ('text','first_zoom','first_x','first_y','second_zoom','second_x','second_y')) then raise exception 'card_layout_invalid';end if;
 foreach k in array array['first_zoom','first_x','first_y','second_zoom','second_x','second_y'] loop
  if p_layout ? k then
   if jsonb_typeof(p_layout->k)<>'number' then raise exception 'card_layout_invalid';end if;
   x:=(p_layout->>k)::numeric;
   if (k like '%zoom' and (x<1 or x>4)) or (k not like '%zoom' and (x<0 or x>1)) then raise exception 'card_layout_invalid';end if;
  end if;
 end loop;
 perform 1 from mefrion_private.photos where id in (p_first,p_second) and pet_id=p_pet and state='ready' order by id for share;
 if (select count(*) from mefrion_private.photos where id in (p_first,p_second) and pet_id=p_pet and state='ready')<>2 then raise exception 'card_photo_scope';end if;
 select * into v from mefrion_private.cards where actor_id=auth.uid() and request_key=p_key for update;
 if found then if v.pet_id<>p_pet or v.first_id<>p_first or v.second_id<>p_second or v.layout<>p_layout then raise exception 'idempotency_conflict';end if;return v.id;end if;
 insert into mefrion_private.cards(pet_id,first_id,second_id,layout,actor_id,request_key) values(p_pet,p_first,p_second,p_layout,auth.uid(),p_key) returning * into v;
 insert into mefrion_private.audit(actor_id,pet_id,action) values(auth.uid(),p_pet,'card.create');return v.id;
end $$;
create function public.mefrion_cards(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'first',c.first_id,'second',c.second_id,'layout',c.layout,'mine',c.actor_id=auth.uid()) order by c.created_at desc,c.id),'[]') from mefrion_private.cards c join mefrion_private.photos a on a.id=c.first_id and a.state='ready' join mefrion_private.photos b on b.id=c.second_id and b.state='ready' where c.pet_id=p_pet);
end $$;
create function public.mefrion_delete_card(p_card uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare v mefrion_private.cards;
begin
 perform mefrion_private.require_registered();select * into v from mefrion_private.cards where id=p_card for update;
 if not found or v.actor_id<>auth.uid() or not public.mefrion_family_access(v.pet_id) then raise exception 'provider_required' using errcode='42501';end if;
 delete from mefrion_private.cards where id=p_card;return true;
end $$;
create function public.mefrion_family_activity(p_pet uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id::text,'action',action,'mine',actor_id=auth.uid(),'created_at',created_at) order by created_at desc,id desc),'[]') from (select * from mefrion_private.audit where pet_id=p_pet and action in ('photo.create','photo.finish','photo.delete','pet.update','invite.accept','member.remove','card.create') order by created_at desc,id desc limit 50) a);
end $$;
create function public.mefrion_family_new(p_pet uuid) returns integer language plpgsql stable security definer set search_path='' as $$
begin
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 return (select count(*)::integer from mefrion_private.photos where pet_id=p_pet and state='ready' and provider_id<>auth.uid() and coalesce(ready_at,created_at)>coalesce((select seen_at from mefrion_private.family_reads where pet_id=p_pet and user_id=auth.uid()),'-infinity'::timestamptz));
end $$;
create function public.mefrion_mark_family_read(p_pet uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();perform 1 from mefrion_private.pets where id=p_pet for share;
 if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
 insert into mefrion_private.family_reads values(p_pet,auth.uid(),now()) on conflict(pet_id,user_id) do update set seen_at=excluded.seen_at;return true;
end $$;
create function public.mefrion_edit_event(p_event uuid,p_captured text,p_title text,p_kind text,p_note text) returns boolean language plpgsql security definer set search_path='' as $$
declare v mefrion_private.pet_events;
begin
 perform mefrion_private.require_registered();select * into v from mefrion_private.pet_events where id=p_event for update;
 if not found or v.actor_id<>auth.uid() or not public.mefrion_family_access(v.pet_id) then raise exception 'provider_required' using errcode='42501';end if;
 if not mefrion_private.valid_partial_date(p_captured) or p_title is null or length(btrim(p_title)) not between 1 and 30 or p_kind is null or p_kind not in ('birthday','anniversary','arrival','hospital','other') or p_note is null or length(p_note)>200 then raise exception 'event_invalid';end if;
 update mefrion_private.pet_events set captured=p_captured,title=btrim(p_title),event_kind=p_kind,note=p_note where id=p_event;return true;
end $$;
create function public.mefrion_authorize_card_export(p_card uuid,p_explicit boolean) returns boolean language plpgsql stable security definer set search_path='' as $$
declare v mefrion_private.cards;
begin
 perform mefrion_private.require_registered();
 if p_explicit is distinct from true then raise exception 'export_confirmation_required';end if;
 select c.* into v from mefrion_private.cards c join mefrion_private.pets p on p.id=c.pet_id and p.owner_id=auth.uid() where c.id=p_card;
 if not found or not public.mefrion_family_access(v.pet_id) then raise exception 'owner_required' using errcode='42501';end if;
 if (select count(*) from mefrion_private.photos p join mefrion_private.consents consent on consent.photo_id=p.id and consent.purpose='external_share' and consent.allowed where p.id in (v.first_id,v.second_id) and p.pet_id=v.pet_id and p.state='ready')<>2 then raise exception 'provider_export_consent_required' using errcode='42501';end if;return true;
end $$;
revoke execute on function public.mefrion_authorize_card_export(uuid,boolean) from public,anon;
grant execute on function public.mefrion_authorize_card_export(uuid,boolean) to authenticated;
create function mefrion_private.family_retirement_cleanup() returns trigger language plpgsql security definer set search_path='' as $$
begin
 delete from mefrion_private.cards where actor_id=new.user_id;
 delete from mefrion_private.family_reads where user_id=new.user_id or pet_id in (select id from mefrion_private.pets where owner_id=new.user_id);
 return new;
end $$;
create trigger mefrion_family_retirement after insert on mefrion_private.account_retirements for each row execute function mefrion_private.family_retirement_cleanup();
create function mefrion_private.photo_ready_activity() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.state='ready' and old.state<>'ready' then new.ready_at:=now();insert into mefrion_private.audit(actor_id,pet_id,action) values(new.provider_id,new.pet_id,'photo.finish');end if;return new;
end $$;
create trigger mefrion_photo_ready_activity before update of state on mefrion_private.photos for each row execute function mefrion_private.photo_ready_activity();
revoke execute on function mefrion_private.photo_ready_activity() from public,anon,authenticated;
revoke execute on function mefrion_private.family_retirement_cleanup() from public,anon,authenticated;
revoke execute on function public.mefrion_save_card(uuid,uuid,uuid,jsonb,uuid),public.mefrion_cards(uuid),public.mefrion_delete_card(uuid),public.mefrion_family_activity(uuid),public.mefrion_family_new(uuid),public.mefrion_mark_family_read(uuid),public.mefrion_edit_event(uuid,text,text,text,text) from public,anon;
grant execute on function public.mefrion_save_card(uuid,uuid,uuid,jsonb,uuid),public.mefrion_cards(uuid),public.mefrion_delete_card(uuid),public.mefrion_family_activity(uuid),public.mefrion_family_new(uuid),public.mefrion_mark_family_read(uuid),public.mefrion_edit_event(uuid,text,text,text,text) to authenticated;
commit;
