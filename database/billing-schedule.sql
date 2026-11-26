-- Run after billing-automation.sql in the existing Supabase SQL Editor.
-- Supabase's default cron timezone is UTC; 16:05 UTC is 00:05 Asia/Manila.
begin;
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('waterdistrict-billing-daily','5 16 * * *','select public.wd_billing_run_daily();');
commit;
-- Verify execution in Integrations > Cron > waterdistrict-billing-daily.
