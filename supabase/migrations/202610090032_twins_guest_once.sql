begin;
create or replace function public.mefrion_twins_begin(p_key uuid,p_hash text,p_species text) returns jsonb language plpgsql security definer set search_path='' as $$
declare t mefrion_private.twins_searches;cap integer;used integer;new_id uuid;
begin
 perform mefrion_private.require_twins_actor();
 if p_key is null or p_hash is null or p_hash!~'^[a-f0-9]{64}$' or p_species is null or p_species not in ('dog','cat') then raise exception 'search_invalid';end if;
 perform pg_advisory_xact_lock(hashtextextended('twins:'||auth.uid()::text,0));
 select * into t from mefrion_private.twins_searches where actor_id=auth.uid() and request_key=p_key;
 if found then if t.input_hash<>p_hash or t.species<>p_species then raise exception 'idempotency_conflict';end if;return jsonb_build_object('id',t.id,'state',t.state);end if;
 cap:=case when coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then 1 else 5 end;
 select count(*) into used from mefrion_private.twins_searches where actor_id=auth.uid() and (cap=1 or (created_at at time zone 'Asia/Tokyo')::date=(now() at time zone 'Asia/Tokyo')::date);
 if used>=cap then raise exception 'daily_search_limit' using errcode='P0001';end if;
 insert into mefrion_private.twins_searches(actor_id,request_key,input_hash,species) values(auth.uid(),p_key,p_hash,p_species) returning id into new_id;
 return jsonb_build_object('id',new_id,'state','pending','remaining',cap-used-1);
end $$;
create or replace function public.mefrion_twins_history() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform mefrion_private.require_registered();return (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'state',s.state,'species',s.species,'created_at',s.created_at,'candidates',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'pet_id',p.id,'name',p.name,'species',p.species)),'[]') from unnest(s.candidates) i join mefrion_private.twins_candidates c on c.id=i join mefrion_private.pets p on p.id=c.pet_id where mefrion_private.twins_visible(c.id,auth.uid()))) order by s.created_at desc),'[]') from (select * from mefrion_private.twins_searches where actor_id=auth.uid() and created_at>now()-interval '30 days' order by created_at desc limit 50) s);
end $$;
commit;
