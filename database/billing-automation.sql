-- Existing Supabase project: run this entire transaction as the project owner.
-- Existing unpaid bills accrue simple 1%/day from their original due date.
-- Existing fully paid bills stay settled. No records/accounts are removed.
begin;

create schema if not exists wd_billing_private;
revoke all on schema wd_billing_private from public,anon,authenticated,service_role;

create sequence if not exists wd_billing_private.bill_number_seq start 1000000000 maxvalue 9999999999 no cycle;
create sequence if not exists wd_billing_private.payment_reference_seq start 1000000000 maxvalue 9999999999 no cycle;

alter table public.bills
 add column if not exists base_amount_due numeric(12,2),
 add column if not exists interest_amount numeric(12,2) not null default 0,
 add column if not exists interest_days integer not null default 0,
 add column if not exists request_id uuid,
 add column if not exists automatic_cycle date;
update public.bills set base_amount_due=amount_due where base_amount_due is null;
alter table public.bills alter column base_amount_due set not null;
alter table public.offline_payments add column if not exists request_id uuid;
create unique index if not exists wd_bill_request_unique on public.bills(request_id) where request_id is not null;
create unique index if not exists wd_payment_request_unique on public.offline_payments(request_id) where request_id is not null;
create unique index if not exists wd_bill_account_cycle_unique on public.bills(account_id,automatic_cycle) where automatic_cycle is not null;

create table if not exists public.billing_plans(
 account_id uuid primary key references public.service_accounts(id) on delete restrict,
 monthly_amount numeric(12,2) not null check(monthly_amount>0),
 enabled boolean not null default true,
 next_issue_date date not null check(extract(day from next_issue_date)=28),
 updated_by uuid not null references public.profiles(user_id),
 updated_at timestamptz not null default now()
);
alter table public.billing_plans enable row level security;
revoke all on public.billing_plans from public,anon,authenticated;
grant select on public.billing_plans to authenticated;
do $policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='billing_plans' and policyname='wd_admin_billing_plans') then
  create policy wd_admin_billing_plans on public.billing_plans for select to authenticated using(
   exists(select 1 from public.profiles where user_id=auth.uid() and active and role='admin'));
 end if;
 -- Keep the existing policy; add the same Admin rule using the district date.
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='offline_payments' and policyname='wd_admin_manila_payments') then
  create policy wd_admin_manila_payments on public.offline_payments for insert to authenticated with check(
   verified_by=auth.uid() and payment_date<=(clock_timestamp() at time zone 'Asia/Manila')::date
   and exists(select 1 from public.profiles where user_id=auth.uid() and active and role='admin'));
 end if;
end $policy$;

create or replace function wd_billing_private.today() returns date
language sql volatile set search_path=pg_catalog as $fn$
 select (clock_timestamp() at time zone 'Asia/Manila')::date
$fn$;

create or replace function wd_billing_private.require_admin() returns uuid
language plpgsql stable security definer set search_path=pg_catalog as $fn$
begin
 if not exists(select 1 from public.profiles where user_id=auth.uid() and active and role='admin') then
  raise exception 'Active administrator required' using errcode='42501';
 end if;
 return auth.uid();
end $fn$;

create or replace function wd_billing_private.accrue(p_bill uuid,p_as_of date) returns void
language plpgsql security definer set search_path=pg_catalog as $fn$
declare b public.bills%rowtype; paid numeric; days integer; interest numeric;
begin
 select * into b from public.bills where id=p_bill for update;
 if b.id is null then raise exception 'Bill unavailable' using errcode='P0002'; end if;
 select coalesce(sum(amount_paid),0) into paid from public.offline_payments where bill_id=b.id;
 -- Once the recorded total is fully paid, never add another day's interest.
 if paid>=b.amount_due then return; end if;
 days:=greatest(0,p_as_of-b.due_date);
 if days<=b.interest_days then return; end if;
 interest:=round(b.base_amount_due*0.01*days,2);
 update public.bills set interest_days=days,interest_amount=interest,
  amount_due=base_amount_due+interest where id=b.id;
end $fn$;

create or replace function wd_billing_private.bill_insert() returns trigger
language plpgsql security definer set search_path=pg_catalog as $fn$
declare ref text; today date:=wd_billing_private.today();
begin
 -- A cron-issued bill supplies its plan owner; every interactive caller is Admin.
 if auth.uid() is not null then new.created_by:=wd_billing_private.require_admin(); end if;
 if new.amount_due is null or new.amount_due<=0 or new.amount_due<>round(new.amount_due,2) then
  raise exception 'Positive bill amount required' using errcode='22023'; end if;
 loop
  ref:='MWD-'||to_char(today,'YYYYMM')||'-'||nextval('wd_billing_private.bill_number_seq');
  exit when not exists(select 1 from public.bills where bill_number=ref);
 end loop;
 new.bill_number:=ref;
 new.billing_period_start:=coalesce(new.billing_period_start,date_trunc('month',today)::date);
 new.billing_period_end:=coalesce(new.billing_period_end,(date_trunc('month',today)+interval '1 month - 1 day')::date);
 new.base_amount_due:=new.amount_due;new.interest_amount:=0;new.interest_days:=0;
 new.created_at:=clock_timestamp();
 return new;
end $fn$;
drop trigger if exists wd_billing_bill_insert on public.bills;
create trigger wd_billing_bill_insert before insert on public.bills for each row execute function wd_billing_private.bill_insert();

create or replace function wd_billing_private.payment_insert() returns trigger
language plpgsql security definer set search_path=pg_catalog as $fn$
declare total numeric; paid numeric; ref text;
begin
 new.verified_by:=wd_billing_private.require_admin();new.verified_at:=clock_timestamp();
 if new.payment_date is null or new.payment_date>wd_billing_private.today() then
  raise exception 'Payment date cannot be in the future' using errcode='22023'; end if;
 perform wd_billing_private.accrue(new.bill_id,wd_billing_private.today());
 select amount_due into total from public.bills where id=new.bill_id for update;
 select coalesce(sum(amount_paid),0) into paid from public.offline_payments where bill_id=new.bill_id;
 if new.amount_paid is null or new.amount_paid<=0 or new.amount_paid>total-paid then
  raise exception 'Payment exceeds the current balance or bill is fully paid' using errcode='22023'; end if;
 loop
  ref:=nextval('wd_billing_private.payment_reference_seq')::text;
  exit when not exists(select 1 from public.offline_payments where receipt_reference=ref);
 end loop;
 new.receipt_reference:=ref;
 return new;
end $fn$;
drop trigger if exists wd_billing_payment_insert on public.offline_payments;
create trigger wd_billing_payment_insert before insert on public.offline_payments for each row execute function wd_billing_private.payment_insert();

create or replace function public.wd_billing_set_plan(p_account_id uuid,p_monthly_amount numeric,p_enabled boolean) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor uuid:=wd_billing_private.require_admin(); today date:=wd_billing_private.today(); issue date;
begin
 if p_monthly_amount is null or p_monthly_amount<=0 or p_monthly_amount>9999999999.99 or p_monthly_amount<>round(p_monthly_amount,2) or p_enabled is null then
  raise exception 'Positive monthly amount and enabled state required' using errcode='22023'; end if;
 if not exists(select 1 from public.service_accounts where id=p_account_id and active) then
  raise exception 'Active service account required' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(28831001);
 issue:=date_trunc('month',today)::date+27;
 if issue<today then issue:=(issue+interval '1 month')::date; end if;
 insert into public.billing_plans(account_id,monthly_amount,enabled,next_issue_date,updated_by)
 values(p_account_id,p_monthly_amount,p_enabled,issue,actor)
 on conflict(account_id) do update set monthly_amount=excluded.monthly_amount,enabled=excluded.enabled,
  next_issue_date=case when billing_plans.enabled then billing_plans.next_issue_date else excluded.next_issue_date end,
  updated_by=actor,updated_at=clock_timestamp();
 -- Configuring on the 28th after the daily job must still issue on the 28th.
 perform wd_billing_private.run(today);
 return (select to_jsonb(p) from public.billing_plans p where account_id=p_account_id);
end $fn$;

create or replace function public.wd_billing_create_bill(p_request_id uuid,p_account_id uuid,p_amount numeric,p_due_date date) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor uuid:=wd_billing_private.require_admin(); b public.bills%rowtype;
begin
 if p_request_id is null or p_due_date is null or p_due_date<wd_billing_private.today()
  or p_amount is null or p_amount<=0 or p_amount>9999999999.99 or p_amount<>round(p_amount,2) then
  raise exception 'Valid request, positive amount and current/future due date required' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
 select * into b from public.bills where request_id=p_request_id;
 if found then
  if b.account_id<>p_account_id or b.created_by<>actor or b.base_amount_due<>p_amount or b.due_date<>p_due_date then
   raise exception 'Request already used with different details' using errcode='40001'; end if;
  return to_jsonb(b);
 end if;
 if not exists(select 1 from public.service_accounts where id=p_account_id and active) then raise exception 'Active account required' using errcode='22023'; end if;
 insert into public.bills(request_id,account_id,amount_due,due_date,created_by)
 values(p_request_id,p_account_id,p_amount,p_due_date,actor) returning * into b;
 return to_jsonb(b);
end $fn$;

create or replace function public.wd_billing_confirm_payment(p_request_id uuid,p_bill_id uuid,p_amount numeric,p_payment_date date) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor uuid:=wd_billing_private.require_admin(); p public.offline_payments%rowtype;
begin
 if p_request_id is null or p_amount is null or p_amount<=0 or p_amount>9999999999.99 or p_amount<>round(p_amount,2) then
  raise exception 'Valid request and positive two-decimal payment required' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
 select * into p from public.offline_payments where request_id=p_request_id;
 if found then
  if p.bill_id<>p_bill_id or p.verified_by<>actor or p.amount_paid<>p_amount or p.payment_date is distinct from p_payment_date then
   raise exception 'Request already used with different details' using errcode='40001'; end if;
  return to_jsonb(p);
 end if;
 insert into public.offline_payments(request_id,bill_id,amount_paid,payment_date,verified_by)
 values(p_request_id,p_bill_id,p_amount,p_payment_date,actor) returning * into p;
 return to_jsonb(p);
end $fn$;

-- Private date argument permits deterministic local tests; never exposed by REST.
create or replace function wd_billing_private.run(p_as_of date) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $fn$
declare plan public.billing_plans%rowtype; b record; issued integer:=0;
begin
 perform pg_advisory_xact_lock(28831001);
 for plan in select p.* from public.billing_plans p join public.service_accounts a on a.id=p.account_id
  where p.enabled and a.active and p.next_issue_date<=p_as_of order by p.account_id for update of p loop
  while plan.next_issue_date<=p_as_of loop
   insert into public.bills(account_id,amount_due,due_date,billing_period_start,billing_period_end,created_by,automatic_cycle)
   values(plan.account_id,plan.monthly_amount,plan.next_issue_date+3,date_trunc('month',plan.next_issue_date)::date,
    (date_trunc('month',plan.next_issue_date)+interval '1 month - 1 day')::date,plan.updated_by,plan.next_issue_date)
   on conflict(account_id,automatic_cycle) where automatic_cycle is not null do nothing;
   if found then issued:=issued+1; end if;
   plan.next_issue_date:=(plan.next_issue_date+interval '1 month')::date;
  end loop;
  update public.billing_plans set next_issue_date=plan.next_issue_date where account_id=plan.account_id;
 end loop;
 for b in select id from public.bills where due_date<p_as_of and interest_days<p_as_of-due_date order by id loop
  perform wd_billing_private.accrue(b.id,p_as_of);
 end loop;
 return jsonb_build_object('issued',issued,'asOf',p_as_of);
end $fn$;

create or replace function public.wd_billing_run_daily() returns jsonb
language sql security definer set search_path=pg_catalog as $fn$
 select wd_billing_private.run(wd_billing_private.today())
$fn$;

create or replace function public.wd_billing_refresh() returns jsonb
language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor uuid:=auth.uid(); actor_role text; b record; today date:=wd_billing_private.today();
begin
 select role into actor_role from public.profiles where user_id=actor and active;
 if actor_role is null or actor_role not in ('admin','client') then raise exception 'Active billing access required' using errcode='42501'; end if;
 for b in select id from public.bills where due_date<today and interest_days<today-due_date
  and (actor_role='admin' or exists(select 1 from public.account_access a where a.account_id=bills.account_id and a.user_id=actor and a.active)) order by id loop
  perform wd_billing_private.accrue(b.id,today);
 end loop;
 return jsonb_build_object('asOf',today);
end $fn$;

create or replace function public.wd_billing_status() returns jsonb
language plpgsql security definer set search_path=pg_catalog as $fn$
declare enabled boolean:=false;
begin
 perform wd_billing_private.require_admin();
 if to_regclass('cron.job') is not null then
  execute $query$select exists(select 1 from cron.job where jobname='waterdistrict-billing-daily'
   and active and schedule='5 16 * * *' and command='select public.wd_billing_run_daily();')$query$ into enabled;
 end if;
 return jsonb_build_object('scheduleActive',enabled,'timezone','Asia/Manila','dailyRun','00:05');
end $fn$;

revoke all on all functions in schema wd_billing_private from public,anon,authenticated,service_role;
revoke all on all sequences in schema wd_billing_private from public,anon,authenticated,service_role;
revoke all on function public.wd_billing_run_daily() from public,anon,authenticated,service_role;
revoke all on function public.wd_billing_set_plan(uuid,numeric,boolean),public.wd_billing_create_bill(uuid,uuid,numeric,date),
 public.wd_billing_confirm_payment(uuid,uuid,numeric,date),public.wd_billing_refresh(),public.wd_billing_status() from public,anon,authenticated,service_role;
grant execute on function public.wd_billing_set_plan(uuid,numeric,boolean),public.wd_billing_create_bill(uuid,uuid,numeric,date),
 public.wd_billing_confirm_payment(uuid,uuid,numeric,date),public.wd_billing_refresh(),public.wd_billing_status() to authenticated;

-- Apply the chosen interest rule to existing unpaid bills immediately. No new
-- recurring bill is issued until its account has an enabled monthly plan.
select public.wd_billing_run_daily();
notify pgrst,'reload schema';
commit;
