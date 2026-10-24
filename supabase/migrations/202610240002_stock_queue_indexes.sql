begin;
create index stock_asset_history on mefrion_private.stock_tasks(asset_id,state);
-- Avoid scanning old reservations and expose exhausted crash retries for operators.
create index stock_task_lease on mefrion_private.stock_tasks(lease_until) where state='processing';
create function mefrion_private.stock_expire_leases() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 update mefrion_private.stock_tasks set state='failed',error_code='lease_exhausted'
  where state='processing' and lease_until<now() and attempts>=12;
 return new;
end $$;
revoke all on function mefrion_private.stock_expire_leases() from public,anon,authenticated;
create trigger stock_recover_exhausted before insert on mefrion_private.stock_runs for each statement execute function mefrion_private.stock_expire_leases();
commit;
