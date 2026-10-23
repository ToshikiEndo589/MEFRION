begin;
create or replace function mefrion_private.retirement_write_gate() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if auth.role()='authenticated' then
  perform mefrion_private.require_registered();
  -- A family operation can have checked scope before waiting for the owner's
  -- retirement transaction. Recheck the current parent after the row lock.
  if tg_table_name in ('photos','members','invites') then
   perform 1 from mefrion_private.pets where id=new.pet_id for share;
   if exists(select 1 from mefrion_private.pets p join mefrion_private.account_retirements r on r.user_id=p.owner_id where p.id=new.pet_id) then raise exception 'pet_retired' using errcode='42501';end if;
  end if;
 end if;
 return new;
end $$;
commit;
