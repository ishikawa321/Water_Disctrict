-- Run once in the existing Supabase SQL Editor after billing-automation.sql.
-- Replaces the fixed 28th rule. Existing bills, payments and plan dates remain.
begin;

alter table public.bills add column if not exists release_date date;
update public.bills set release_date=(created_at at time zone 'Asia/Manila')::date where release_date is null;
alter table public.bills alter column release_date set default ((clock_timestamp() at time zone 'Asia/Manila')::date);
alter table public.bills alter column release_date set not null;

-- Restrictive policy intersects all existing Consumer SELECT policies, preserving
-- account isolation even if more than one permissive read policy exists.
drop policy if exists wd_bill_release_visibility on public.bills;
create policy wd_bill_release_visibility on public.bills as restrictive for select to authenticated using(
 release_date <= (clock_timestamp() at time zone 'Asia/Manila')::date
 or exists(select 1 from public.profiles where user_id=auth.uid() and active and role in ('admin','staff'))
);

-- Remove only the original fixed-day constraint; retain every other constraint.
alter table public.billing_plans drop constraint if exists billing_plans_next_issue_date_check;
alter table public.billing_plans add column if not exists release_day integer;
update public.billing_plans set release_day=extract(day from next_issue_date)::integer where release_day is null;
alter table public.billing_plans alter column release_day set not null;
do $migration$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.billing_plans'::regclass and conname='billing_plans_release_day_check') then
  alter table public.billing_plans add constraint billing_plans_release_day_check check(release_day between 1 and 31);
 end if;
end $migration$;

create or replace function wd_billing_private.run(p_as_of date) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $fn$
declare plan public.billing_plans%rowtype; b record; issued integer:=0; next_month date;
begin
 perform pg_advisory_xact_lock(28831001);
 for plan in select p.* from public.billing_plans p join public.service_accounts a on a.id=p.account_id
  where p.enabled and a.active and p.next_issue_date<=p_as_of order by p.account_id for update of p loop
  while plan.next_issue_date<=p_as_of loop
   insert into public.bills(account_id,amount_due,due_date,release_date,billing_period_start,billing_period_end,created_by,automatic_cycle)
   values(plan.account_id,plan.monthly_amount,plan.next_issue_date+3,plan.next_issue_date,date_trunc('month',plan.next_issue_date)::date,
    (date_trunc('month',plan.next_issue_date)+interval '1 month - 1 day')::date,plan.updated_by,plan.next_issue_date)
   on conflict(account_id,automatic_cycle) where automatic_cycle is not null do nothing;
   if found then issued:=issued+1; end if;
   next_month:=(date_trunc('month',plan.next_issue_date)+interval '1 month')::date;
   plan.next_issue_date:=least(next_month+plan.release_day-1,(next_month+interval '1 month - 1 day')::date);
  end loop;
  update public.billing_plans set next_issue_date=plan.next_issue_date where account_id=plan.account_id;
 end loop;
 for b in select id from public.bills where due_date<p_as_of and interest_days<p_as_of-due_date order by id loop
  perform wd_billing_private.accrue(b.id,p_as_of);
 end loop;
 return jsonb_build_object('issued',issued,'asOf',p_as_of);
end $fn$;

create or replace function public.wd_billing_set_plan(p_account_id uuid,p_monthly_amount numeric,p_enabled boolean,p_release_date date) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor uuid:=wd_billing_private.require_admin(); today date:=wd_billing_private.today();
begin
 if p_monthly_amount is null or p_monthly_amount<=0 or p_monthly_amount>9999999999.99 or p_monthly_amount<>round(p_monthly_amount,2)
  or p_enabled is null or p_release_date is null or p_release_date<today or p_release_date>date '2100-12-31' then
  raise exception 'Positive monthly amount, enabled state and current/future release date required' using errcode='22023'; end if;
 if not exists(select 1 from public.service_accounts where id=p_account_id and active) then
  raise exception 'Active service account required' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(28831001);
 insert into public.billing_plans(account_id,monthly_amount,enabled,next_issue_date,release_day,updated_by)
 values(p_account_id,p_monthly_amount,p_enabled,p_release_date,extract(day from p_release_date)::integer,actor)
 on conflict(account_id) do update set monthly_amount=excluded.monthly_amount,enabled=excluded.enabled,
  next_issue_date=excluded.next_issue_date,release_day=excluded.release_day,updated_by=actor,updated_at=clock_timestamp();
 perform wd_billing_private.run(today);
 return (select to_jsonb(p) from public.billing_plans p where account_id=p_account_id);
end $fn$;

-- Compatibility for older callers: retain their saved future date or use today.
-- The fixed 28th rule is never used, including through the old signature.
create or replace function public.wd_billing_set_plan(p_account_id uuid,p_monthly_amount numeric,p_enabled boolean) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $fn$
declare release date;
begin
 perform wd_billing_private.require_admin();
 select greatest(next_issue_date,wd_billing_private.today()) into release from public.billing_plans where account_id=p_account_id;
 return public.wd_billing_set_plan(p_account_id,p_monthly_amount,p_enabled,coalesce(release,wd_billing_private.today()));
end $fn$;

create or replace function public.wd_billing_create_bill(p_request_id uuid,p_account_id uuid,p_amount numeric,p_due_date date,p_release_date date) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor uuid:=wd_billing_private.require_admin(); b public.bills%rowtype;
begin
 if p_request_id is null or p_release_date is null or p_release_date<wd_billing_private.today() or p_release_date>date '2100-12-31'
  or p_due_date is null or p_due_date<p_release_date or p_due_date>date '2100-12-31'
  or p_amount is null or p_amount<=0 or p_amount>9999999999.99 or p_amount<>round(p_amount,2) then
  raise exception 'Valid request, positive amount and due date on/after the release date required' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
 select * into b from public.bills where request_id=p_request_id;
 if found then
  if b.account_id<>p_account_id or b.created_by<>actor or b.base_amount_due<>p_amount or b.due_date<>p_due_date or b.release_date<>p_release_date then
   raise exception 'Request already used with different details' using errcode='40001'; end if;
  return to_jsonb(b);
 end if;
 if not exists(select 1 from public.service_accounts where id=p_account_id and active) then raise exception 'Active account required' using errcode='22023'; end if;
 insert into public.bills(request_id,account_id,amount_due,due_date,release_date,created_by)
 values(p_request_id,p_account_id,p_amount,p_due_date,p_release_date,actor) returning * into b;
 return to_jsonb(b);
end $fn$;

create or replace function public.wd_billing_create_bill(p_request_id uuid,p_account_id uuid,p_amount numeric,p_due_date date) returns jsonb
language sql security definer set search_path=pg_catalog as $fn$
 select public.wd_billing_create_bill(p_request_id,p_account_id,p_amount,p_due_date,wd_billing_private.today())
$fn$;

revoke all on function public.wd_billing_set_plan(uuid,numeric,boolean,date),public.wd_billing_create_bill(uuid,uuid,numeric,date,date) from public,anon,authenticated,service_role;
grant execute on function public.wd_billing_set_plan(uuid,numeric,boolean,date),public.wd_billing_create_bill(uuid,uuid,numeric,date,date) to authenticated;
revoke all on all functions in schema wd_billing_private from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
