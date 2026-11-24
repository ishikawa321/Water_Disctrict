-- Run in this project's Supabase SQL Editor as postgres.
-- Assign up to five active client profiles in email order. Admins are excluded.
-- All changes roll back together if a constraint or an ownership check fails.
-- Existing linked accounts keep their holder name, address, bills and payments.
-- New links use relationship 'holder' and a clearly marked demo reference.
begin;

do $$
declare
  client_record record;
  service_id public.service_accounts.id%type;
  audit_user uuid;
  next_number text;
  link_count integer;
  client_count integer;
begin
  lock table public.profiles, public.service_accounts, public.account_access
    in share row exclusive mode;

  select count(*) into client_count
    from public.profiles p join auth.users u on u.id = p.user_id
    where p.role = 'client' and p.active = true;
  if client_count = 0 then
    raise exception 'No active client profiles found. No accounts were changed.';
  end if;
  if client_count > 5 then
    raise exception 'There are % active clients, but only five requested demo numbers. No accounts were changed.', client_count;
  end if;

  -- Required by the service account audit field; this does not link the admin.
  select user_id into audit_user from public.profiles
    where role = 'admin' and active = true order by user_id limit 1;
  if audit_user is null then
    raise exception 'An active administrator profile is required for the account audit field.';
  end if;

  for client_record in
    select p.user_id, p.display_name, u.email,
      row_number() over (order by lower(u.email), p.user_id) as position
    from public.profiles p join auth.users u on u.id = p.user_id
    where p.role = 'client' and p.active = true
    order by lower(u.email), p.user_id
  loop
    next_number := 'MWD-' || lpad((1244 + client_record.position)::text, 6, '0');
    service_id := null;
    select count(*) into link_count from public.account_access
      where user_id = client_record.user_id;
    if link_count > 1 then
      raise exception 'Client % has multiple account links; review these before assigning a number.', client_record.email;
    end if;
    if link_count = 1 then
      select account_id into service_id from public.account_access
        where user_id = client_record.user_id;
      if exists (select 1 from public.account_access
        where account_id = service_id and user_id <> client_record.user_id) then
        raise exception 'Client % shares a service account with another user. No accounts were changed.', client_record.email;
      end if;
    end if;

    if exists (select 1 from public.service_accounts
      where account_number = next_number and id is distinct from service_id) then
      raise exception 'Account number % already belongs to a different record. No accounts were changed.', next_number;
    end if;

    if service_id is null then
      insert into public.service_accounts
        (account_number, holder_name, service_address, active, updated_by)
      values (next_number,
        coalesce(nullif(btrim(client_record.display_name), ''), split_part(client_record.email, '@', 1)),
        'Demo service address - replace with the verified address', true, audit_user)
      returning id into service_id;
      insert into public.account_access
        (user_id, account_id, relationship, authorization_reference,
         verified_by, verified_at, active)
      values (client_record.user_id, service_id, 'holder',
        'DEMO-SEQUENTIAL-' || next_number, audit_user, now(), true);
    else
      update public.service_accounts
        set account_number = next_number, updated_by = audit_user
        where id = service_id;
      -- Preserve existing relationships and authorization references.
      -- Reactivation must clear revoked_at to satisfy the database constraint.
      update public.account_access
        set active = true, revoked_at = null,
            verified_by = audit_user, verified_at = now()
        where user_id = client_record.user_id and account_id = service_id
          and active = false;
    end if;
  end loop;
end $$;

commit;

-- Confirm the saved assignments. No administrator should appear here.
select u.email, p.display_name, s.account_number, s.holder_name, s.service_address
from public.profiles p
join auth.users u on u.id = p.user_id
join public.account_access a on a.user_id = p.user_id and a.active = true
join public.service_accounts s on s.id = a.account_id
where p.role = 'client' and p.active = true
order by lower(u.email), p.user_id;
