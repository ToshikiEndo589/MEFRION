-- The comments function itself checks that the post remains publicly allowed.
-- Restore read access for guests without granting any write or private access.
begin;
revoke execute on function public.mefrion_comments(uuid) from public;
grant execute on function public.mefrion_comments(uuid) to anon,authenticated;
commit;
