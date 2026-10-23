begin;

-- Only the signed-in account can inspect its own follows or the followers of
-- its own Pets. The response contains public Pet fields and a comment alias,
-- never a follower's email address or private family data.
create or replace function public.mefrion_social_connections(
  p_kind text, p_offset integer default 0, p_limit integer default 40
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform mefrion_private.require_registered();
  if p_kind not in ('following','followers') or p_offset is null or p_offset < 0 or p_offset > 10000
     or p_limit is null or p_limit < 1 or p_limit > 50 then
    raise exception 'connections_invalid';
  end if;
  if p_kind = 'following' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', f.pet_id::text, 'name', pet.name, 'species', pet.species,
      'breed', case when 'breed'=any(pet.public_fields) then pet.breed else '' end,
      'profile_pet_id', pet.id, 'followed_pet_name', null
    ) order by f.created_at desc, f.pet_id desc),'[]'::jsonb) into result
    from (select f.* from mefrion_private.follows f
      join mefrion_private.pets pet on pet.id=f.pet_id
      join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled
      where f.actor_id=auth.uid()
        and mefrion_private.social_actor_visible(auth.uid(),pet.owner_id)
      order by f.created_at desc,f.pet_id desc limit p_limit offset p_offset) f
    join mefrion_private.pets pet on pet.id=f.pet_id;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', f.actor_id::text||':'||f.pet_id::text,
      'name', coalesce(nullif(public_pet.name,''),nullif(identity.name,''),'フォロワー'),
      'species', public_pet.species,
      'breed', case when 'breed'=any(public_pet.public_fields) then public_pet.breed else '' end,
      'profile_pet_id', public_pet.id, 'followed_pet_name', followed.name
    ) order by f.created_at desc,f.pet_id desc,f.actor_id desc),'[]'::jsonb) into result
    from (select f.* from mefrion_private.follows f
      join mefrion_private.pets own_pet on own_pet.id=f.pet_id
      where own_pet.owner_id=auth.uid()
        and mefrion_private.social_actor_visible(auth.uid(),f.actor_id)
      order by f.created_at desc,f.pet_id desc,f.actor_id desc limit p_limit offset p_offset) f
    join mefrion_private.pets followed on followed.id=f.pet_id
    left join mefrion_private.social_identities identity on identity.user_id=f.actor_id
    left join lateral (
      select pet.id,pet.name,pet.species,pet.breed,pet.public_fields
      from mefrion_private.pets pet
      join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled
      where pet.owner_id=f.actor_id and mefrion_private.managed_public_ready(pet.id)
      order by pet.id limit 1
    ) public_pet on true;
  end if;
  return result;
end $$;

revoke execute on function public.mefrion_social_connections(text,integer,integer) from public,anon;
grant execute on function public.mefrion_social_connections(text,integer,integer) to authenticated;
commit;
