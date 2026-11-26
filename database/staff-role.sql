-- Run after web-office-workflows.sql and billing-automation.sql, as project owner.
-- Add Staff payments, secure Admin invitations, and Admin-confirmed resolution.
begin;
do $preflight$ begin
 if to_regprocedure('public.wd_web_workflow(text,uuid,bigint,jsonb)') is null
 or to_regprocedure('public.wd_billing_confirm_payment(uuid,uuid,numeric,date)') is null then
 raise exception 'Apply the shared web workflow and billing setup first.'; end if;
end $preflight$;
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check(role in ('admin','staff','client'));
alter table public.repair_tickets drop constraint if exists repair_tickets_status_check;
alter table public.repair_tickets add constraint repair_tickets_status_check check(status in ('Open','Assigned','In progress','Completed','Resolved'));
do $checks$ declare c record; begin
 for c in select conname from pg_constraint where conrelid='public.ticket_status_history'::regclass and contype='c' and pg_get_constraintdef(oid) like '%status%' loop
  execute format('alter table public.ticket_status_history drop constraint %I',c.conname);
 end loop;
 alter table public.ticket_status_history add constraint wd_staff_history_status_check check(status in ('Open','Assigned','In progress','Completed','Resolved'));
end $checks$;
CREATE OR REPLACE FUNCTION public.wd_ticket_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE actor uuid:=public.wd_actor(); office_role text; concern public.service_concerns%ROWTYPE; staff_name text;
BEGIN
 SELECT role INTO office_role FROM public.profiles WHERE user_id=actor AND active FOR SHARE;
 IF office_role IS NULL OR office_role NOT IN ('admin','staff') THEN RAISE EXCEPTION 'Office access required' USING ERRCODE='42501'; END IF;
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Retain repair tickets' USING ERRCODE='42501'; END IF;
 IF COALESCE(length(btrim(NEW.latest_update)),0) NOT BETWEEN 1 AND 3000 THEN RAISE EXCEPTION 'Update note required' USING ERRCODE='23514'; END IF;
 IF TG_OP='INSERT' THEN
 IF office_role<>'admin' THEN RAISE EXCEPTION 'Administrator required' USING ERRCODE='42501'; END IF;
 SELECT * INTO concern FROM public.service_concerns WHERE id=NEW.concern_id FOR UPDATE;
 IF concern.id IS NULL OR concern.status<>'Under review' OR concern.reviewed_by IS NULL OR concern.reviewed_at IS NULL THEN
 RAISE EXCEPTION 'Reviewed concern required' USING ERRCODE='23514'; END IF;
 IF NEW.status IS DISTINCT FROM 'Open' OR NEW.assigned_to_user_id IS NOT NULL THEN RAISE EXCEPTION 'Create an Open ticket before assignment' USING ERRCODE='23514'; END IF;
 NEW.created_by:=actor; NEW.assigned_to:=NULL;
 ELSE
 IF NEW.id<>OLD.id OR NEW.concern_id<>OLD.concern_id OR NEW.created_by<>OLD.created_by THEN RAISE EXCEPTION 'Ticket origin is immutable' USING ERRCODE='23514'; END IF;
 IF office_role='staff' AND (OLD.assigned_to_user_id IS DISTINCT FROM actor OR NEW.assigned_to_user_id IS DISTINCT FROM actor) THEN
 RAISE EXCEPTION 'Only assigned staff can update this ticket' USING ERRCODE='42501'; END IF;
 IF NEW.status='Resolved' AND office_role<>'admin' THEN RAISE EXCEPTION 'Administrator confirmation required' USING ERRCODE='42501'; END IF;
 IF OLD.status='Completed' AND office_role<>'admin' THEN RAISE EXCEPTION 'Awaiting administrator confirmation' USING ERRCODE='42501'; END IF;
 IF NOT COALESCE(((OLD.status='Open' AND NEW.status IN ('Open','Assigned')) OR (OLD.status='Assigned' AND NEW.status IN ('Assigned','In progress')) OR
 (OLD.status='In progress' AND NEW.status IN ('In progress','Completed')) OR (OLD.status='Completed' AND NEW.status IN ('Completed','In progress','Resolved'))),false) THEN RAISE EXCEPTION 'Invalid ticket transition' USING ERRCODE='23514'; END IF;
 END IF;
 IF NEW.status='Open' THEN
 IF NEW.assigned_to_user_id IS NOT NULL THEN RAISE EXCEPTION 'Use Assigned status for assignment' USING ERRCODE='23514'; END IF;
 NEW.assigned_to:=NULL;
 ELSE
 SELECT display_name INTO staff_name FROM public.profiles WHERE user_id=NEW.assigned_to_user_id AND active AND role='staff' FOR SHARE;
 IF staff_name IS NULL THEN RAISE EXCEPTION 'Active staff assignment required' USING ERRCODE='23514'; END IF;
 NEW.assigned_to:=staff_name;
 END IF;
 NEW.updated_by:=actor; NEW.updated_at:=clock_timestamp(); RETURN NEW;
END $fn$;

-- Original event trigger resolves the concern only for Resolved, never Completed.
create or replace function public.wd_is_active_office() returns boolean
language sql stable security definer set search_path=pg_catalog as $$
 select exists(select 1 from public.profiles where user_id=auth.uid() and active and role in ('admin','staff'))
$$;
revoke all on function public.wd_is_active_office() from public,anon;
grant execute on function public.wd_is_active_office() to authenticated;
do $policies$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='bills' and policyname='wd_staff_bills_read') then
 create policy wd_staff_bills_read on public.bills for select to authenticated using(public.wd_web_is_staff()); end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='offline_payments' and policyname='wd_staff_payments_read') then
 create policy wd_staff_payments_read on public.offline_payments for select to authenticated using(public.wd_web_is_staff()); end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='offline_payments' and policyname='wd_staff_confirm_payment') then
 create policy wd_staff_confirm_payment on public.offline_payments for insert to authenticated with check(public.wd_web_is_staff() and verified_by=auth.uid() and payment_date<=(clock_timestamp() at time zone 'Asia/Manila')::date); end if;
end $policies$;

-- Dedicated payment authority; billing settings/issuance keep require_admin().
create or replace function wd_billing_private.require_payment_officer() returns uuid
language plpgsql stable security definer set search_path=pg_catalog as $$
begin
 if not public.wd_is_active_office() then raise exception 'Active payment officer required' using errcode='42501'; end if;
 return auth.uid();
end $$;
create or replace function wd_billing_private.payment_insert() returns trigger
language plpgsql security definer set search_path=pg_catalog as $fn$
declare total numeric; paid numeric; ref text;
begin
 new.verified_by:=wd_billing_private.require_payment_officer();new.verified_at:=clock_timestamp();
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

create or replace function public.wd_billing_confirm_payment(p_request_id uuid,p_bill_id uuid,p_amount numeric,p_payment_date date) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor uuid:=wd_billing_private.require_payment_officer(); p public.offline_payments%rowtype;
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


create or replace function public.wd_billing_refresh() returns jsonb
language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor uuid:=auth.uid(); actor_role text; b record; today date:=wd_billing_private.today();
begin
 select role into actor_role from public.profiles where user_id=actor and active;
 if actor_role is null or actor_role not in ('admin','staff','client') then raise exception 'Active billing access required' using errcode='42501'; end if;
 for b in select id from public.bills where due_date<today and interest_days<today-due_date
  and (actor_role in ('admin','staff') or exists(select 1 from public.account_access a where a.account_id=bills.account_id and a.user_id=actor and a.active)) order by id loop
  perform wd_billing_private.accrue(b.id,today);
 end loop;
 return jsonb_build_object('asOf',today);
end $fn$;



create table if not exists public.staff_invitations(
 id uuid primary key default gen_random_uuid(),email text not null,display_name text not null check(length(btrim(display_name)) between 1 and 200),
 token_hash text not null,status text not null default 'Pending' check(status in ('Pending','Accepted','Revoked')),
 invited_by uuid not null references public.profiles(user_id),invited_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '7 days',
 user_id uuid references auth.users(id),accepted_at timestamptz
);
create unique index if not exists wd_pending_staff_email on public.staff_invitations(lower(email)) where status='Pending';
alter table public.staff_invitations enable row level security;
revoke all on public.staff_invitations from public,anon,authenticated;
grant select(id,email,display_name,status,invited_at,expires_at,user_id,accepted_at) on public.staff_invitations to authenticated;
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='staff_invitations' and policyname='wd_staff_invite_read') then
 create policy wd_staff_invite_read on public.staff_invitations for select to authenticated using(public.wd_is_active_admin() or user_id=auth.uid()); end if;
end $$;
create or replace function public.wd_staff_invite(p_email text,p_display_name text) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
declare actor uuid:=wd_billing_private.require_admin(); token text:=gen_random_uuid()::text; invitation uuid; invite_email text:=lower(btrim(p_email));
begin
 if invite_email is null or length(invite_email)>254 or invite_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
 or coalesce(length(btrim(p_display_name)),0) not between 1 and 200 then raise exception 'Valid email and name required' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(invite_email,183));
 if exists(select 1 from auth.users u where lower(u.email)=invite_email) then raise exception 'This email already has an account. Use a new Staff email; existing users cannot be promoted through invitations.' using errcode='22023'; end if;
 update public.staff_invitations set status='Revoked' where lower(staff_invitations.email)=invite_email and status='Pending';
 insert into public.staff_invitations(email,display_name,token_hash,invited_by) values(invite_email,btrim(p_display_name),md5(token),actor) returning id into invitation;
 return jsonb_build_object('id',invitation,'token',token,'email',invite_email);
end $$;
create or replace function public.wd_staff_invitation(p_token text) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog as $$
declare i public.staff_invitations%rowtype;
begin
 select * into i from public.staff_invitations where token_hash=md5(p_token) and status='Pending' and expires_at>now();
 if not found or not exists(select 1 from public.profiles where user_id=i.invited_by and active and role='admin') then raise exception 'Invitation expired or revoked' using errcode='22023'; end if;
 return jsonb_build_object('email',i.email,'displayName',i.display_name,'expiresAt',i.expires_at);
end $$;
create or replace function public.wd_staff_access(p_user_id uuid,p_active boolean) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
begin
 perform wd_billing_private.require_admin();
 if p_active is null then raise exception 'Active state required' using errcode='22023'; end if;
 update public.profiles set active=p_active where user_id=p_user_id and role='staff';
 if not found then raise exception 'Staff member unavailable' using errcode='P0002'; end if;
 return jsonb_build_object('userId',p_user_id,'active',p_active);
end $$;
create or replace function public.wd_staff_revoke_invite(p_id uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog as $$
begin
 perform wd_billing_private.require_admin();
 update public.staff_invitations set status='Revoked' where id=p_id and status='Pending';
 return jsonb_build_object('id',p_id);
end $$;
create or replace function public.wd_staff_directory() returns jsonb
language plpgsql stable security definer set search_path=pg_catalog as $$
begin
 perform wd_billing_private.require_admin();
 return(select coalesce(jsonb_agg(jsonb_build_object('userId',p.user_id,'displayName',p.display_name,'role',p.role,'active',p.active,'email',u.email) order by p.display_name),'[]'::jsonb) from public.profiles p join auth.users u on u.id=p.user_id where p.role in ('admin','staff'));
end $$;
create or replace function public.wd_provision_invited_staff() returns trigger
language plpgsql security definer set search_path=pg_catalog as $$
declare i public.staff_invitations%rowtype; token text:=new.raw_user_meta_data->>'staff_invite_token';
begin
 if new.raw_user_meta_data->>'registration_source' is distinct from 'staff_invite_v1' then return new; end if;
 select * into i from public.staff_invitations where token_hash=md5(token) for update;
 if not found then raise exception 'Staff invitation required' using errcode='42501'; end if;
 if i.status='Accepted' and i.user_id=new.id then return new; end if;
 if i.status<>'Pending' or i.expires_at<=now() or lower(new.email)<>lower(i.email)
 or (i.user_id is not null and i.user_id<>new.id)
 or not exists(select 1 from public.profiles where user_id=i.invited_by and active and role='admin') then raise exception 'Invitation expired, revoked or email does not match' using errcode='42501'; end if;
 if exists(select 1 from public.profiles where user_id=new.id and role<>'staff')
 or exists(select 1 from public.account_access where user_id=new.id) then raise exception 'Existing identity cannot become Staff through signup' using errcode='42501'; end if;
 insert into public.profiles(user_id,display_name,role,active) values(new.id,i.display_name,'staff',new.email_confirmed_at is not null)
 on conflict(user_id) do update set active=excluded.active where profiles.role='staff';
 update public.staff_invitations set user_id=new.id,status=case when new.email_confirmed_at is null then 'Pending' else 'Accepted' end,
 accepted_at=case when new.email_confirmed_at is null then null else now() end where id=i.id;
 return new;
end $$;
drop trigger if exists zz_provision_invited_staff on auth.users;
create trigger zz_provision_invited_staff after insert or update of email_confirmed_at on auth.users for each row execute function public.wd_provision_invited_staff();
revoke all on function public.wd_staff_invite(text,text),public.wd_staff_access(uuid,boolean),public.wd_staff_revoke_invite(uuid),public.wd_staff_directory(),public.wd_staff_invitation(text),public.wd_provision_invited_staff() from public,anon,authenticated;
grant execute on function public.wd_staff_invite(text,text),public.wd_staff_access(uuid,boolean),public.wd_staff_revoke_invite(uuid),public.wd_staff_directory() to authenticated;
grant execute on function public.wd_staff_invitation(text) to anon,authenticated;
revoke all on function wd_billing_private.require_payment_officer() from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
commit;
