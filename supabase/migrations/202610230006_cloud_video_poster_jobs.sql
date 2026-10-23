begin;
-- Transcoding a video and decoding its poster must not share an invocation's
-- memory budget. They are distinct durable tasks and finalize together.
create or replace function mefrion_private.cloud_job_current(j mefrion_private.cloud_jobs) returns boolean
language sql stable security definer set search_path='' as $$
 select case j.payload->>'flow'
 when 'publication' then exists(
  select 1 from mefrion_private.public_posts s
  join mefrion_private.public_media m on m.post_id=s.id
  join mefrion_private.photos p on p.id=m.source_id
  join mefrion_private.consents c on c.photo_id=p.id and c.purpose=case when s.kind='post' then 'sns' else 'external_share' end
  join mefrion_private.public_profiles f on f.pet_id=s.pet_id and f.enabled
  where s.id=j.entity_id and s.state in ('pending','processing','published') and p.state='ready'
   and c.allowed and c.version=m.consent_version and m.object_path=coalesce(j.payload->>'media_path',j.object_path)
   and (p.object_path=j.payload->>'source_path' or p.preview_path=j.payload->>'source_path')
 )
 when 'twins' then mefrion_private.twins_source_valid(j.entity_id)
 when 'twins_share' then mefrion_private.twins_share_other(j.entity_id,null)
 else true end
$$;
do $migration$
declare source text;needle text:='values(case when m->>''kind''=''video'' then ''video'' else ''image'' end,(j->>''id'')::uuid,m->>''path'',m||jsonb_build_object(''flow'',''publication'')) on conflict do nothing;';
addition text:=$addition$
   if m->>'kind'='video' then
    insert into mefrion_private.cloud_jobs(kind,entity_id,object_path,payload)
     values('image',(j->>'id')::uuid,left(m->>'path',length(m->>'path')-4)||'.jpg',
      jsonb_build_object('flow','publication','media_path',m->>'path','source_path',left(m->>'source_path',length(m->>'source_path')-4)||'-preview.jpg')) on conflict do nothing;
   end if;$addition$;
begin
 source:=pg_get_functiondef('mefrion_private.cloud_tick()'::regprocedure);
 if position(needle in source)=0 then raise exception 'cloud dispatcher changed; inspect before applying';end if;
 execute replace(source,needle,needle||addition);
end $migration$;
commit;
