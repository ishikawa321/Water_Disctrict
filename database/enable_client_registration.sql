-- Apply once through Supabase SQL Editor as postgres, before enabling signup.
-- Existing accounts, numbers, profiles and links are preserved.
begin;

-- A transactional counter serializes signups; failed transactions consume no number.
create table if not exists public.client_account_number_counter (
  singleton boolean primary key default true check (singleton),
  last_value bigint not null check (last_value >= 0)
);
alter table public.client_account_number_counter enable row level security;
revoke all on public.client_account_number_counter from public, anon, authenticated;
insert into public.client_account_number_counter (singleton, last_value)
select true, coalesce(max(substring(account_number from '^MWD-([0-9]+)$')::bigint), 0)
from public.service_accounts
on conflict (singleton) do nothing;

create or replace function public.provision_registered_client()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  holder text;
  address text;
  next_value bigint;
  number text;
  service_id uuid;
  existing_role text;
  existing_active boolean;
begin
  -- Metadata never determines a role or an existing account to attach to.
  -- Provision only this explicit signup flow, once the email is confirmed.
  if new.email_confirmed_at is null
     or new.raw_user_meta_data ->> 'registration_source' is distinct from 'client_signup_v1' then
    return new;
  end if;

  -- Serialize repeated confirmation events for the same identity.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.id::text, 7319));
  select role, active into existing_role, existing_active
    from public.profiles where user_id = new.id for update;
  if existing_role is not null and (existing_role <> 'client' or not existing_active) then
    return new; -- Never replace, promote or reactivate a provisioned profile.
  end if;
  if exists (select 1 from public.account_access where user_id = new.id) then
    return new; -- Never duplicate, relink or reactivate an existing service link.
  end if;

  holder := btrim(new.raw_user_meta_data ->> 'display_name');
  address := btrim(new.raw_user_meta_data ->> 'service_address');
  if holder is null or length(holder) not between 1 and 200
     or address is null or length(address) not between 1 and 500 then
    raise exception 'Full name and service address are required for client registration.';
  end if;
  insert into public.profiles (user_id, display_name, role, active)
    values (new.id, holder, 'client', true)
    on conflict (user_id) do nothing;

  select last_value into next_value from public.client_account_number_counter
    where singleton = true for update;
  -- Reconcile higher existing MWD numbers without changing any saved number.
  select greatest(next_value,
    coalesce(max(substring(account_number from '^MWD-([0-9]+)$')::bigint), 0)) + 1
    into next_value from public.service_accounts;
  number := 'MWD-' || lpad(next_value::text, greatest(6, length(next_value::text)), '0');
  update public.client_account_number_counter set last_value = next_value where singleton = true;
  insert into public.service_accounts (account_number, holder_name, service_address, active, updated_by)
    values (number, holder, address, true, new.id) returning id into service_id;
  insert into public.account_access
    (user_id, account_id, relationship, authorization_reference, verified_by, verified_at, active)
    values (new.id, service_id, 'holder', 'SELF-REGISTRATION:' || new.id::text,
      new.id, now(), true);
  -- verified_by records the registering identity, not a fictitious office verifier.
  -- This creates a NEW account; it never asserts ownership of an existing one.
  return new;
end;
$$;
revoke all on function public.provision_registered_client() from public, anon, authenticated;
drop trigger if exists zz_provision_registered_client on auth.users;
create trigger zz_provision_registered_client
  after insert or update of email_confirmed_at on auth.users
  for each row execute function public.provision_registered_client();

-- Clients fail closed before signup when this migration has not been installed.
create or replace function public.client_registration_available()
returns boolean language sql stable set search_path = '' as $$ select true $$;
revoke all on function public.client_registration_available() from public;
grant execute on function public.client_registration_available() to anon, authenticated;

-- Manual creation is replaced by the trusted signup trigger. Other policies stay intact.
drop policy if exists "Active administrators can create service accounts" on public.service_accounts;
revoke insert on public.service_accounts from authenticated;
notify pgrst, 'reload schema';
commit;
