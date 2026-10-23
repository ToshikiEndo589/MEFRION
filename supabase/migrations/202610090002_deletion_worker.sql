begin;
create or replace function public.mefrion_deletion_batch() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'server_only' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'path',object_path)),'[]'::jsonb) from (select id,object_path from mefrion_private.deletion_outbox where state='pending' order by created_at limit 20) q);
end $$;
create or replace function public.mefrion_deletion_ack(p_id uuid,p_path text) returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'server_only' using errcode='42501';end if;
 update mefrion_private.deletion_outbox set state='done' where id=p_id and object_path=p_path;
 return found;
end $$;
revoke execute on function public.mefrion_deletion_batch(),public.mefrion_deletion_ack(uuid,text) from public,anon,authenticated;
grant execute on function public.mefrion_deletion_batch(),public.mefrion_deletion_ack(uuid,text) to service_role;
commit;
