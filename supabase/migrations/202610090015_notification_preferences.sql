begin;
create table mefrion_private.notification_preferences(user_id uuid primary key references auth.users(id),settings jsonb not null);
alter table mefrion_private.notification_preferences enable row level security;
revoke all on mefrion_private.notification_preferences from public,anon,authenticated;
create or replace function public.mefrion_notification_preferences() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return coalesce((select settings from mefrion_private.notification_preferences where user_id=auth.uid()),'{"like":true,"comment":true,"follow":true,"twins":false}'::jsonb);
end $$;
create or replace function public.mefrion_set_notification_preferences(p_settings jsonb) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 if p_settings is null or jsonb_typeof(p_settings)<>'object' or (select count(*) from jsonb_object_keys(p_settings))<>4 or not (p_settings ?& array['like','comment','follow','twins']) then raise exception 'preferences_invalid';end if;
 if exists(select 1 from jsonb_each(p_settings) where jsonb_typeof(value)<>'boolean') then raise exception 'preferences_boolean_required';end if;
 insert into mefrion_private.notification_preferences values(auth.uid(),p_settings) on conflict(user_id) do update set settings=excluded.settings;
 return true;
end $$;
revoke execute on function public.mefrion_notification_preferences(),public.mefrion_set_notification_preferences(jsonb) from public,anon;
grant execute on function public.mefrion_notification_preferences(),public.mefrion_set_notification_preferences(jsonb) to authenticated;
create or replace function public.mefrion_social_notifications() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',n.id,'kind',n.kind,'name',case when n.kind in ('comment','reply') then (select speaker_name from mefrion_private.social_comments c where c.id::text=n.event_key) else coalesce(i.name,'ユーザー') end,'pet_name',p.name,'pet_id',p.id,'post_id',n.post_id,'created_at',n.created_at) order by n.created_at desc),'[]'::jsonb)
 from (select * from mefrion_private.social_notifications where recipient_id=auth.uid() order by created_at desc limit 50) n
 join mefrion_private.pets p on p.id=n.pet_id join mefrion_private.public_profiles profile on profile.pet_id=p.id and profile.enabled
 left join mefrion_private.social_identities i on i.user_id=n.actor_id
 where coalesce((select settings->>case when n.kind='reply' then 'comment' else n.kind end from mefrion_private.notification_preferences where user_id=auth.uid()),'true')='true' and mefrion_private.social_actor_visible(auth.uid(),n.actor_id) and (n.post_id is null or mefrion_private.post_allowed(n.post_id,auth.uid())) and (n.kind not in ('comment','reply') or exists(select 1 from mefrion_private.social_comments c where c.id::text=n.event_key and c.state='active' and mefrion_private.comment_visible(c.id,auth.uid()))));
end $$;
commit;
