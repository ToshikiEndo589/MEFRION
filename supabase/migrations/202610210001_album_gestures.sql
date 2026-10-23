-- Private, family-scoped labels for the pet gesture album.
begin;

create table mefrion_private.gesture_photos (
  pet_id uuid not null references mefrion_private.pets(id) on delete cascade,
  photo_id uuid not null references mefrion_private.photos(id) on delete cascade,
  gesture text not null check (gesture in ('sleep','lick','sit','belly','run','look')),
  added_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (photo_id, gesture)
);
create index gesture_photos_pet_idx on mefrion_private.gesture_photos(pet_id, gesture);
alter table mefrion_private.gesture_photos enable row level security;
revoke all on mefrion_private.gesture_photos from public, anon, authenticated;

create function public.mefrion_album_gestures(p_pet uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not public.mefrion_family_access(p_pet) then
    raise exception 'permission_required' using errcode='42501';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'photo_id', g.photo_id, 'gesture', g.gesture
    ) order by g.created_at desc, g.photo_id), '[]'::jsonb)
    from mefrion_private.gesture_photos g
    join mefrion_private.photos p on p.id=g.photo_id and p.pet_id=g.pet_id and p.state='ready'
    where g.pet_id=p_pet
  );
end $$;

create function public.mefrion_set_album_gesture(p_pet uuid,p_photo uuid,p_gesture text,p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$
begin
  perform mefrion_private.require_registered();
  if p_pet is null or p_photo is null or p_enabled is null or p_gesture is null or
     p_gesture not in ('sleep','lick','sit','belly','run','look') or
     not public.mefrion_family_access(p_pet) then
    raise exception 'permission_required' using errcode='42501';
  end if;
  if not exists (
    select 1 from mefrion_private.photos
    where id=p_photo and pet_id=p_pet and state='ready'
  ) then
    raise exception 'photo_not_found' using errcode='22023';
  end if;
  if p_enabled then
    insert into mefrion_private.gesture_photos(pet_id,photo_id,gesture,added_by)
    values (p_pet,p_photo,p_gesture,auth.uid())
    on conflict(photo_id,gesture) do nothing;
  else
    delete from mefrion_private.gesture_photos
    where pet_id=p_pet and photo_id=p_photo and gesture=p_gesture;
  end if;
  return true;
end $$;

revoke execute on function public.mefrion_album_gestures(uuid),
  public.mefrion_set_album_gesture(uuid,uuid,text,boolean) from public, anon;
grant execute on function public.mefrion_album_gestures(uuid),
  public.mefrion_set_album_gesture(uuid,uuid,text,boolean) to authenticated;
commit;
