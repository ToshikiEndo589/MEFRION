-- A new public post and a family album entry are different user actions.
-- Keep the original in private storage for revocation and reuse, but only
-- include it in the family album when the user explicitly chose that path.
begin;
alter table mefrion_private.photos add column if not exists album_visible boolean not null default true;

create or replace function public.mefrion_set_album_visibility(p_photo uuid,p_visible boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare item mefrion_private.photos;
begin
  perform mefrion_private.require_registered();
  if p_visible is null then raise exception 'visibility_required';end if;
  select * into item from mefrion_private.photos where id=p_photo and provider_id=auth.uid() and state='ready' for update;
  if not found or not public.mefrion_family_access(item.pet_id) then raise exception 'permission_required' using errcode='42501';end if;
  update mefrion_private.photos set album_visible=p_visible where id=p_photo;
  return true;
end $$;
revoke all on function public.mefrion_set_album_visibility(uuid,boolean) from public,anon;
grant execute on function public.mefrion_set_album_visibility(uuid,boolean) to authenticated;

create or replace function public.mefrion_own_post_video_source(p_post uuid)
returns uuid language plpgsql stable security definer set search_path='' as $$
declare source_id uuid;
begin
  perform mefrion_private.require_registered();
  select photo.id into source_id from mefrion_private.public_posts s
  join mefrion_private.public_media m on m.post_id=s.id
  join mefrion_private.photos photo on photo.id=m.source_id and photo.media_kind='video' and photo.state='ready'
  where s.id=p_post and s.actor_id=auth.uid() order by m.position limit 1;
  return source_id;
end $$;
revoke all on function public.mefrion_own_post_video_source(uuid) from public,anon;
grant execute on function public.mefrion_own_post_video_source(uuid) to authenticated;

create or replace function public.mefrion_album(p_pet uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not public.mefrion_family_access(p_pet) then raise exception 'permission_required' using errcode='42501';end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'path',object_path,'captured',captured,'created_at',created_at,'title',title,'mine',provider_id=auth.uid(),'event_kind',event_kind,'note',note,'provider_name',mefrion_private.family_display_name(p_pet,provider_id),'media_kind',media_kind,'duration_seconds',duration_seconds) order by captured desc nulls last,created_at desc,id),'[]')
    from mefrion_private.photos where pet_id=p_pet and state='ready' and album_visible);
end $$;

-- Earlier quick-post videos used the same upload route as the album. Only
-- recent user-origin videos uploaded immediately for a post are backfilled.
update mefrion_private.photos p set album_visible=false
where p.media_kind='video' and p.album_visible and exists (
  select 1 from mefrion_private.public_media m
  join mefrion_private.public_posts s on s.id=m.post_id
  where m.source_id=p.id and s.kind='post' and s.content_origin='user'
    and s.actor_id=p.provider_id and p.created_at between s.created_at-interval '10 minutes' and s.created_at
);
commit;
