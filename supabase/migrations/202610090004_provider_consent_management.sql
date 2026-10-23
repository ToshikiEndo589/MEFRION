-- A former family member can inspect ONLY their own consent records.
-- Never return original paths, images, private Pet profiles, or other providers.
begin;
create or replace function public.mefrion_provided_photos() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();
 return (select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'captured',p.captured,'title',p.title,
  'sns',coalesce((select allowed from mefrion_private.consents c where c.photo_id=p.id and c.purpose='sns'),false),
  'twins',coalesce((select allowed from mefrion_private.consents c where c.photo_id=p.id and c.purpose='twins'),false),
  'external_share',coalesce((select allowed from mefrion_private.consents c where c.photo_id=p.id and c.purpose='external_share'),false)
 ) order by p.created_at desc),'[]'::jsonb)
 from mefrion_private.photos p where p.provider_id=auth.uid() and p.state='ready');
end $$;
revoke execute on function public.mefrion_provided_photos() from public,anon;
grant execute on function public.mefrion_provided_photos() to authenticated;
commit;
