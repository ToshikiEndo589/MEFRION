begin;
-- Do not stop an otherwise valid publication if a storage write is not yet
-- visible in the finalizer transaction. Keep the missing media retryable.
do $migration$
declare source text;needle text:='if flow=''publication'' then finished:=public.mefrion_publication_finish(j.entity_id);';
replacement text:=$replacement$if flow='publication' then
    if exists(select 1 from mefrion_private.public_media m where m.post_id=j.entity_id and not exists(select 1 from storage.objects o where o.bucket_id='public-derived' and o.name=m.object_path)) then
     update mefrion_private.cloud_jobs task set state='pending',available_at=now()+interval '10 seconds',error_code='object_not_visible'
      where task.entity_id=j.entity_id and task.kind in ('image','video') and exists(select 1 from mefrion_private.public_media m where m.post_id=j.entity_id and m.object_path=task.object_path and not exists(select 1 from storage.objects o where o.bucket_id='public-derived' and o.name=m.object_path));
     return true;
    end if;
    update mefrion_private.public_posts set state='processing' where id=j.entity_id and state='pending';
    finished:=public.mefrion_publication_finish(j.entity_id);$replacement$;
begin
 source:=pg_get_functiondef('public.mefrion_cloud_work_complete(uuid,uuid,boolean,text,integer)'::regprocedure);
 if position(needle in source)=0 then raise exception 'cloud finalizer changed; inspect before applying';end if;
 execute replace(source,needle,replacement);
end $migration$;
commit;
