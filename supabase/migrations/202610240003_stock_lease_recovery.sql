begin;
drop trigger stock_recover_exhausted on mefrion_private.stock_runs;
drop function mefrion_private.stock_expire_leases();
do $$
declare src text;needle text:='perform mefrion_private.stock_plan();';
begin
 src:=pg_get_functiondef('public.mefrion_stock_batch()'::regprocedure);
 if position(needle in src)=0 then raise exception 'stock_batch_changed';end if;
 execute replace(src,needle,'update mefrion_private.stock_tasks set state=''failed'',error_code=''lease_exhausted'' where state=''processing'' and lease_until<now() and attempts>=12; '||needle);
end $$;
commit;
