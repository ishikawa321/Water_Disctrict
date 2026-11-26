-- Run after enable_client_registration.sql. Existing approved/linked accounts stay unchanged.
begin;
create table if not exists public.client_registrations (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (length(btrim(full_name)) between 1 and 200),
  service_address text not null check (length(btrim(service_address)) between 1 and 500),
  email text not null,
  status text not null default 'Pending' check (status in ('Pending','Approved')),
  submitted_at timestamptz not null default now(),
  email_confirmed_at timestamptz,
  approved_by uuid references public.profiles(user_id),
  approved_at timestamptz,
  account_id uuid references public.service_accounts(id),
  constraint client_registration_approval_check check (
    (status='Pending' and approved_by is null and approved_at is null and account_id is null)
    or (status='Approved' and approved_by is not null and approved_at is not null and account_id is not null))
);
alter table public.client_registrations enable row level security;
revoke all on public.client_registrations from public, anon, authenticated;
grant select on public.client_registrations to authenticated;
drop policy if exists "Read own registration" on public.client_registrations;
create policy "Read own registration" on public.client_registrations for select to authenticated
  using (user_id=(select auth.uid()));
drop policy if exists "Admin reads client registrations" on public.client_registrations;
create policy "Admin reads client registrations" on public.client_registrations for select to authenticated
  using (exists(select 1 from public.profiles where user_id=(select auth.uid()) and role='admin' and active));

-- Replace automatic activation with a pending, inactive client profile on signup.
create or replace function public.provision_registered_client()
returns trigger language plpgsql security definer set search_path='' as $$
declare holder text; address text;
begin
  if new.raw_user_meta_data->>'registration_source' is distinct from 'client_signup_v1' then return new; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.id::text,7319));
  if exists(select 1 from public.client_registrations where user_id=new.id) then
    update public.client_registrations set email_confirmed_at=new.email_confirmed_at where user_id=new.id;
    return new; -- Confirmation never activates or reopens a registration.
  end if;
  if exists(select 1 from public.profiles where user_id=new.id)
     or exists(select 1 from public.account_access where user_id=new.id) then return new; end if;
  holder:=btrim(new.raw_user_meta_data->>'display_name');
  address:=btrim(new.raw_user_meta_data->>'service_address');
  if holder is null or length(holder) not between 1 and 200
     or address is null or length(address) not between 1 and 500 then
    raise exception 'Full name and service address are required for client registration.';
  end if;
  insert into public.client_registrations(user_id,full_name,service_address,email,email_confirmed_at)
    values(new.id,holder,address,new.email,new.email_confirmed_at);
  insert into public.profiles(user_id,display_name,role,active) values(new.id,holder,'client',false);
  return new;
end; $$;
revoke all on function public.provision_registered_client() from public,anon,authenticated;

-- Capture pending signups from the preceding version without changing any existing profile/link.
insert into public.client_registrations(user_id,full_name,service_address,email,email_confirmed_at)
select u.id,btrim(u.raw_user_meta_data->>'display_name'),btrim(u.raw_user_meta_data->>'service_address'),u.email,u.email_confirmed_at
from auth.users u where u.raw_user_meta_data->>'registration_source'='client_signup_v1'
  and length(btrim(u.raw_user_meta_data->>'display_name')) between 1 and 200
  and length(btrim(u.raw_user_meta_data->>'service_address')) between 1 and 500
  and not exists(select 1 from public.profiles p where p.user_id=u.id)
  and not exists(select 1 from public.account_access a where a.user_id=u.id)
on conflict(user_id) do nothing;
insert into public.profiles(user_id,display_name,role,active)
select r.user_id,r.full_name,'client',false from public.client_registrations r where r.status='Pending'
on conflict(user_id) do nothing;

create or replace function public.approve_client_registration(registration_user_id uuid)
returns table(account_number text) language plpgsql security definer set search_path='' as $$
declare reviewer uuid:=auth.uid(); request public.client_registrations%rowtype;
  next_value bigint; number text; service_id uuid;
begin
  if not exists(select 1 from public.profiles where user_id=reviewer and role='admin' and active) then
    raise exception 'Only an active administrator can approve registrations.' using errcode='42501';
  end if;
  select * into request from public.client_registrations where user_id=registration_user_id for update;
  if not found then raise exception 'Registration not found.' using errcode='P0002'; end if;
  if request.status='Approved' then
    return query select s.account_number from public.service_accounts s where s.id=request.account_id;
    return;
  end if;
  perform 1 from public.profiles where user_id=request.user_id and role='client' and not active for update;
  if not found or exists(select 1 from public.account_access where user_id=request.user_id) then
    raise exception 'Registration no longer matches an inactive, unlinked client. Refresh before approving.';
  end if;
  select c.last_value into next_value from public.client_account_number_counter c where c.singleton for update;
  select greatest(next_value,coalesce(max(substring(s.account_number from '^MWD-([0-9]+)$')::bigint),0))+1
    into next_value from public.service_accounts s;
  number:='MWD-'||lpad(next_value::text,greatest(6,length(next_value::text)),'0');
  update public.client_account_number_counter set last_value=next_value where singleton;
  insert into public.service_accounts(account_number,holder_name,service_address,active,updated_by)
    values(number,request.full_name,request.service_address,true,reviewer) returning id into service_id;
  insert into public.account_access(user_id,account_id,relationship,authorization_reference,verified_by,verified_at,active)
    values(request.user_id,service_id,'holder','REGISTRATION-APPROVAL:'||request.user_id::text,reviewer,now(),true);
  update public.profiles set active=true where user_id=request.user_id and role='client';
  update public.client_registrations set status='Approved',approved_by=reviewer,approved_at=now(),account_id=service_id
    where user_id=request.user_id;
  return query select number;
end; $$;
revoke all on function public.approve_client_registration(uuid) from public,anon;
grant execute on function public.approve_client_registration(uuid) to authenticated;

create or replace function public.client_registration_approval_available()
returns boolean language sql stable set search_path='' as $$ select true $$;
revoke all on function public.client_registration_approval_available() from public;
grant execute on function public.client_registration_approval_available() to anon,authenticated;
notify pgrst,'reload schema';
commit;
