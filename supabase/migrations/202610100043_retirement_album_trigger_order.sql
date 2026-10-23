begin;
-- Album scrubbing updates guarded Pet rows. Run it before the tombstone is
-- inserted; AFTER insert correctly denies all ordinary writes for that actor.
-- This remains an internal, revoked trigger inside the retirement transaction.
drop trigger mefrion_album_retirement on mefrion_private.account_retirements;
create trigger mefrion_album_retirement before insert on mefrion_private.account_retirements for each row execute function mefrion_private.album_retirement_scrub();
commit;
