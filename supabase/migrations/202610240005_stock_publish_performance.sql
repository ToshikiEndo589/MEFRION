begin;
-- Public visibility / licence joins grow with the managed feed. These foreign
-- keys did not previously have indexes beginning with the referenced columns.
create index mefrion_public_post_pet on mefrion_private.public_posts(pet_id);
create index mefrion_public_media_source on mefrion_private.public_media(source_id);
-- A bootstrap run owns a fixed, unique reservation budget. Counting its finished
-- reservations under the shared advisory lock avoids rechecking every published
-- post for every single copy. No request can exceed that run's allocated goal.
do $$
declare src text;needle text:='(select count(*) from mefrion_private.public_posts p where p.content_origin=''managed_seed'' and p.kind=''post'' and mefrion_private.post_allowed(p.id,null)) >= (select target from mefrion_private.stock_policy where singleton)';
begin
 src:=pg_get_functiondef('public.mefrion_stock_complete(uuid,uuid,boolean,text)'::regprocedure);
 if position(needle in src)=0 then raise exception 'stock_completion_changed';end if;
 execute replace(src,needle,'(select count(*) from mefrion_private.stock_tasks where run_id=r.id and state=''done'') >= r.goal');
end $$;
commit;
