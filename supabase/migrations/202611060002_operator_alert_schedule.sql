begin;
-- Idempotently register the schedule already verified in production.
select cron.schedule('mefrion-operator-alerts','*/5 * * * *','select mefrion_private.operator_alert_tick()');
commit;
