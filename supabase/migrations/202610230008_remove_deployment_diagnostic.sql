begin;
-- Remove the temporary fixture-only diagnostic installed during live acceptance.
drop trigger if exists cloud_check_finalization on mefrion_private.public_posts;
drop function if exists mefrion_private.cloud_check_finalization();
delete from mefrion_private.cloud_worker_health where name='finalization-check';
alter table mefrion_private.cloud_worker_health drop column if exists detail;
commit;
