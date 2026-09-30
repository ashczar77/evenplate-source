-- schema.sql schedules these idempotently when pg_cron is installed.
do $$ begin
 if exists(select 1 from cron.job where jobname='evenplate-reset-weekly-free-scans') then
  perform cron.unschedule('evenplate-reset-weekly-free-scans');
 end if;
end $$;
select cron.schedule('evenplate-weekly-quota','0 0 * * 1','select public.reset_weekly_free_scans()');
select cron.schedule('evenplate-recover-analysis','* * * * *','select public.recover_analysis_reservations()');
