-- Run after the migration in the SAME transaction, then ROLLBACK.
-- Uses generated QA identities and fake Storage metadata; no actual files/users.
create temporary table stock_test_results(name text,passed boolean);
create function pg_temp.stock_assert(label text,condition boolean) returns void language plpgsql as $$
begin
 if condition is distinct from true then raise exception 'stock assertion failed: %',label;end if;
 insert into stock_test_results values(label,true);
end $$;
select set_config('mefrion.cloud_tick_running','true',true);
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$
declare qa_publisher uuid:=gen_random_uuid();batch jsonb;t mefrion_private.stock_tasks;other mefrion_private.stock_tasks;
 asset text;second text;baseline integer;r uuid;published uuid;before_count integer;
begin
 insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data) values(qa_publisher,'authenticated','authenticated','stock-rollback-'||qa_publisher||'@example.invalid','{}','{"test_only":true}');
 insert into mefrion_private.managed_publishers(id) values(qa_publisher);
 select count(*) into baseline from mefrion_private.public_posts p where p.content_origin='managed_seed' and p.kind='post' and mefrion_private.post_allowed(p.id,null);
 update mefrion_private.stock_policy set enabled=true,publisher=qa_publisher,target=baseline+2,daily=1;
 select id into asset from public.mefrion_reference_assets where active and withdrawn_at is null and exists(select 1 from storage.objects where bucket_id='reference-thumbnails' and name=file) order by id limit 1;
 select id into second from public.mefrion_reference_assets where active and withdrawn_at is null and id<>asset and exists(select 1 from storage.objects where bucket_id='reference-thumbnails' and name=file) order by id limit 1;
 insert into mefrion_private.stock_catalog(asset_id,name,rights_until,evidence) values(asset,'QA むぎ',now()+interval '30 days','rollback fixture');
 batch:=public.mefrion_stock_batch();
 perform pg_temp.stock_assert('one reserved catalogue asset',jsonb_array_length(batch)=1);
 perform pg_temp.stock_assert('no duplicate reservation',jsonb_array_length(public.mefrion_stock_batch())=0);
 select * into t from mefrion_private.stock_tasks where id=(batch->0->>'id')::uuid;
 perform pg_temp.stock_assert('wrong lease cannot publish',not public.mefrion_stock_complete(t.id,gen_random_uuid(),true));
 begin
  perform public.mefrion_stock_complete(t.id,t.lease,true);
  raise exception 'missing objects accepted';
 exception when raise_exception then
  if sqlerrm<>'stock_objects_missing' then raise;end if;
 end;
 perform pg_temp.stock_assert('missing files rejected',true);
 insert into storage.objects(bucket_id,name,metadata) values('family-originals',t.pet_id::text||'/'||t.photo_id::text||'.jpg','{"size":1000,"mimetype":"image/jpeg"}'),('public-derived',t.media_id::text||'.jpg','{"size":1000,"mimetype":"image/jpeg"}');
 perform pg_temp.stock_assert('bootstrap finalizes',public.mefrion_stock_complete(t.id,t.lease,true));
 perform pg_temp.stock_assert('published feed boundary accepts ready stock',mefrion_private.post_allowed(t.post_id,null));
 perform pg_temp.stock_assert('idempotent completion',public.mefrion_stock_complete(t.id,t.lease,true));
 perform pg_temp.stock_assert('zero engagement eligible',mefrion_private.stock_zero(t.post_id));
 insert into mefrion_private.reactions(actor_id,post_id,kind) values(qa_publisher,t.post_id,'like');
 perform pg_temp.stock_assert('one like protects',not mefrion_private.stock_zero(t.post_id));
 delete from mefrion_private.reactions where post_id=t.post_id;
 insert into mefrion_private.social_comments(actor_id,post_id,speaker_name,body,request_key) values(qa_publisher,t.post_id,'QA','QA comment',gen_random_uuid());
 perform pg_temp.stock_assert('one comment protects',not mefrion_private.stock_zero(t.post_id));
 update mefrion_private.social_comments set state='deleted' where post_id=t.post_id;
 insert into mefrion_private.reactions(actor_id,post_id,kind) values(qa_publisher,t.post_id,'save');
 perform pg_temp.stock_assert('save alone follows specified zero-like-zero-comment rule',mefrion_private.stock_zero(t.post_id));
 update mefrion_private.public_posts set content_origin='user' where id=t.post_id;
 perform pg_temp.stock_assert('UGC never eligible',not mefrion_private.stock_zero(t.post_id));
 update mefrion_private.public_posts set content_origin='managed_seed' where id=t.post_id;
 -- Exercise an atomic daily swap and retirement of its old original.
 update mefrion_private.stock_runs set state='done',completed_at=now() where id=t.run_id;
 insert into mefrion_private.stock_catalog(asset_id,name,rights_until,evidence) values(second,'QA もち',now()+interval '30 days','rollback fixture');
 insert into mefrion_private.stock_runs(day,kind,goal,created_at) values((now() at time zone 'Asia/Tokyo')::date,'daily',1,now()+interval '1 second') returning id into r;
 -- The live pool must not participate in this disposable swap.
 update mefrion_private.public_posts set published_at=now()+interval '1 day' where content_origin='managed_seed' and id<>t.post_id;
 perform mefrion_private.stock_plan();
 batch:=public.mefrion_stock_batch();
 perform pg_temp.stock_assert('daily reserves replacement',jsonb_array_length(batch)=1);
 select * into other from mefrion_private.stock_tasks where id=(batch->0->>'id')::uuid;
 insert into storage.objects(bucket_id,name,metadata) values('family-originals',other.pet_id::text||'/'||other.photo_id::text||'.jpg','{"size":1000,"mimetype":"image/jpeg"}'),('public-derived',other.media_id::text||'.jpg','{"size":1000,"mimetype":"image/jpeg"}');
 perform pg_temp.stock_assert('daily swap finalizes',public.mefrion_stock_complete(other.id,other.lease,true));
 perform pg_temp.stock_assert('old post stopped only after new ready',(select state='stopped' from mefrion_private.public_posts where id=t.post_id) and mefrion_private.post_allowed(other.post_id,null));
 perform pg_temp.stock_assert('old original queued for deletion',exists(select 1 from mefrion_private.deletion_outbox where bucket='family-originals' and object_path=t.pet_id::text||'/'||t.photo_id::text||'.jpg'));
 perform pg_temp.stock_assert('exactly one removed and added',(select victim=t.post_id from mefrion_private.stock_tasks where id=other.id));
 -- Engagement arrives after planning, before the replacement is committed.
 update mefrion_private.stock_runs set goal=2 where id=r;
 perform mefrion_private.stock_plan();
 batch:=public.mefrion_stock_batch();
 perform pg_temp.stock_assert('second daily task staged',jsonb_array_length(batch)=1);
 insert into mefrion_private.reactions(actor_id,post_id,kind) values(qa_publisher,other.post_id,'like');
 select * into t from mefrion_private.stock_tasks where id=(batch->0->>'id')::uuid;
 insert into storage.objects(bucket_id,name,metadata) values('family-originals',t.pet_id::text||'/'||t.photo_id::text||'.jpg','{"size":1000,"mimetype":"image/jpeg"}'),('public-derived',t.media_id::text||'.jpg','{"size":1000,"mimetype":"image/jpeg"}');
 perform pg_temp.stock_assert('late like cancels unsafe replacement',not public.mefrion_stock_complete(t.id,t.lease,true));
 perform pg_temp.stock_assert('liked post remains published',mefrion_private.post_allowed(other.post_id,null));
 perform pg_temp.stock_assert('cancelled replacement not published',not exists(select 1 from mefrion_private.public_posts where id=t.post_id));
 perform pg_temp.stock_assert('one run per day',not exists(select day,kind from mefrion_private.stock_runs group by day,kind having count(*)>1));
 perform pg_temp.stock_assert('worker RPCs private',not has_function_privilege('anon','public.mefrion_stock_batch()','execute') and not has_function_privilege('authenticated','public.mefrion_stock_complete(uuid,uuid,boolean,text)','execute'));
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 begin
  perform public.mefrion_stock_batch();raise exception 'anonymous access accepted';
 exception when insufficient_privilege then null;end;
 perform pg_temp.stock_assert('anonymous worker calls denied',true);
end $$;
select jsonb_build_object('passed',true,'checks',count(*),'results',jsonb_agg(row_to_json(x))) from stock_test_results x;
