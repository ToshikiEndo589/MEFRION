begin;
-- Destination upload/readback and offline DB + media restoration passed before
-- enabling this schedule. Each invocation processes at most four leased tasks.
select cron.schedule('mefrion-offsite-backup','* * * * *','select mefrion_private.offsite_dispatch();');
commit;
