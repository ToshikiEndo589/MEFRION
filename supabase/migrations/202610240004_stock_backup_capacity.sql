begin;
-- The approved catalogue and 1,000 posts exceed the previous 8 MiB snapshot
-- bound. Keep every private stock/rights row; encryption and retention unchanged.
do $$
declare name text;src text;
begin
 foreach name in array array['public.mefrion_cloud_database_snapshot()','mefrion_private.offsite_capture()'] loop
  if to_regprocedure(name) is not null then
   src:=pg_get_functiondef(to_regprocedure(name));
   if position('8388608' in src)=0 then raise exception 'backup_bound_changed';end if;
   execute replace(src,'8388608','33554432');
  end if;
 end loop;
end $$;
commit;
