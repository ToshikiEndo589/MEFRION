begin;
alter table mefrion_private.pet_notification_settings add column changed_at timestamptz not null default now();
create function mefrion_private.pet_notification_changed() returns trigger language plpgsql set search_path='' as $$
begin
 if (old.frequency,old.milestones) is distinct from (new.frequency,new.milestones) then new.changed_at:=now();end if;return new;
end $$;
create trigger pet_notification_changed before update on mefrion_private.pet_notification_settings for each row execute function mefrion_private.pet_notification_changed();
create function public.mefrion_family_notifications() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select coalesce(jsonb_agg(item order by stamp desc),'[]') from (select * from (
 select photo.ready_at stamp,jsonb_build_object('id',photo.id::text,'kind','family_photo','pet_id',pet.id,'pet_name',pet.name,'title','新しい写真が追加されました','count',1,'created_at',photo.ready_at) item
 from mefrion_private.pet_notification_settings setting join mefrion_private.pets pet on pet.id=setting.pet_id join mefrion_private.photos photo on photo.pet_id=pet.id and photo.state='ready' and photo.provider_id<>auth.uid() and photo.ready_at>setting.changed_at
 where setting.user_id=auth.uid() and setting.frequency='immediate' and (setting.paused_until is null or setting.paused_until<now()) and public.mefrion_family_access(pet.id)
 union all
 select max(photo.ready_at),jsonb_build_object('id',pet.id::text||':'||(photo.ready_at at time zone 'Asia/Tokyo')::date::text,'kind','family_digest','pet_id',pet.id,'pet_name',pet.name,'title','家族の新しい写真','count',count(*),'created_at',max(photo.ready_at))
 from mefrion_private.pet_notification_settings setting join mefrion_private.pets pet on pet.id=setting.pet_id join mefrion_private.photos photo on photo.pet_id=pet.id and photo.state='ready' and photo.provider_id<>auth.uid() and photo.ready_at>setting.changed_at
 where setting.user_id=auth.uid() and setting.frequency='batched' and (setting.paused_until is null or setting.paused_until<now()) and public.mefrion_family_access(pet.id) and (photo.ready_at at time zone 'Asia/Tokyo')::date<(now() at time zone 'Asia/Tokyo')::date
 group by pet.id,pet.name,(photo.ready_at at time zone 'Asia/Tokyo')::date
 union all
 select now(),jsonb_build_object('id',e.id::text||':'||(now() at time zone 'Asia/Tokyo')::date::text,'kind','milestone','pet_id',pet.id,'pet_name',pet.name,'title',e.title,'count',1,'created_at',now())
 from mefrion_private.pet_notification_settings setting join mefrion_private.pets pet on pet.id=setting.pet_id join mefrion_private.pet_events e on e.pet_id=pet.id and length(e.captured)=10 and substring(e.captured,6)=to_char(now() at time zone 'Asia/Tokyo','MM-DD') and e.captured<=(now() at time zone 'Asia/Tokyo')::date::text
 where setting.user_id=auth.uid() and setting.milestones and (setting.paused_until is null or setting.paused_until<now()) and coalesce(pet.details->>'life_status','living')<>'deceased' and public.mefrion_family_access(pet.id)
 ) visible where stamp>now()-interval '30 days' order by stamp desc limit 50) bounded);
end $$;
create or replace function mefrion_private.social_notify(p_recipient uuid,p_kind text,p_pet uuid,p_post uuid,p_key text) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_recipient=auth.uid() or not mefrion_private.social_actor_visible(p_recipient,auth.uid()) or coalesce((select settings->>case when p_kind='reply' then 'comment' else p_kind end from mefrion_private.notification_preferences where user_id=p_recipient),'true')<>'true' or not exists(select 1 from mefrion_private.public_profiles where pet_id=p_pet and enabled) or (p_post is not null and not mefrion_private.post_allowed(p_post,p_recipient)) then return;end if;
 insert into mefrion_private.social_notifications(recipient_id,actor_id,kind,pet_id,post_id,event_key) values(p_recipient,auth.uid(),p_kind,p_pet,p_post,p_key) on conflict do nothing;
end $$;
create function public.mefrion_social_notification_groups() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',items->>'id','kind',items->>'kind','name',items->>'name','pet_name',items->>'pet_name','pet_id',items->>'pet_id','post_id',items->>'post_id','created_at',items->>'created_at','count',n) order by items->>'created_at' desc),'[]') from (
 select (array_agg(item order by item->>'created_at' desc))[1] items,count(*) n from jsonb_array_elements(public.mefrion_social_notifications()) item group by item->>'kind',item->>'pet_id',item->>'post_id',left(item->>'created_at',10)) grouped
$$;
revoke execute on function mefrion_private.pet_notification_changed() from public,anon,authenticated;
revoke execute on function public.mefrion_family_notifications(),public.mefrion_social_notification_groups() from public,anon;grant execute on function public.mefrion_family_notifications(),public.mefrion_social_notification_groups() to authenticated;
commit;
