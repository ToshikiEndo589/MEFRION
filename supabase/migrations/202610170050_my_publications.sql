begin;

-- An owner can inspect the server-side status of their own posts, including
-- posts that have not yet been converted to public derivatives. Never return
-- original photo paths or pending media identifiers.
create or replace function public.mefrion_my_publications(p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform mefrion_private.require_registered();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', s.id,
      'pet_id', s.pet_id,
      'pet_name', pet.name,
      'body', s.body,
      'state', s.state,
      'created_at', s.created_at,
      'media', case when s.state = 'published' and mefrion_private.post_allowed(s.id, auth.uid())
        then (select coalesce(jsonb_agg(m.id order by m.position), '[]'::jsonb)
              from mefrion_private.public_media m where m.post_id = s.id)
        else '[]'::jsonb end
    ) order by s.created_at desc, s.id desc)
    from (
      select * from mefrion_private.public_posts
      where actor_id = auth.uid() and kind = 'post'
      order by created_at desc, id desc
      limit least(greatest(coalesce(p_limit, 50), 1), 100)
    ) s
    join mefrion_private.pets pet on pet.id = s.pet_id and pet.owner_id = auth.uid()
  ), '[]'::jsonb);
end $$;

revoke all on function public.mefrion_my_publications(integer) from public, anon;
grant execute on function public.mefrion_my_publications(integer) to authenticated;
commit;
