begin;
create or replace function public.mefrion_public_speakers() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select coalesce(jsonb_agg(jsonb_build_object('id',pet.id,'name',pet.name) order by pet.name),'[]'::jsonb) from mefrion_private.pets pet join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled where pet.owner_id=auth.uid() and mefrion_private.social_actor_visible(auth.uid(),pet.owner_id));
end $$;
create or replace function public.mefrion_social_identity() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select jsonb_build_object('name',name,'last_pet',case when exists(select 1 from mefrion_private.pets pet join mefrion_private.public_profiles profile on profile.pet_id=pet.id and profile.enabled where pet.id=last_pet and pet.owner_id=auth.uid()) then last_pet else null end) from mefrion_private.social_identities where user_id=auth.uid());
end $$;
revoke execute on function public.mefrion_public_speakers() from public,anon;
grant execute on function public.mefrion_public_speakers() to authenticated;
commit;
