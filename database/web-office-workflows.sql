-- Run once in the existing project's Supabase SQL Editor after review.
-- Additive web access; no records, existing policies, roles or history are removed.
begin;

do $preflight$
begin
  if to_regprocedure('public.wd_actor()') is null
     or to_regprocedure('public.wd_is_active_admin()') is null
     or to_regprocedure('public.wd_can_read_ticket(uuid)') is null
     or to_regclass('public.ticket_status_history') is null
     or (select count(*) from pg_trigger where not tgisinternal
         and tgenabled in ('O','A') and tgname in
         ('wd_concern_guard','wd_ticket_guard','wd_ticket_event','wd_history_guard')) <> 4 then
    raise exception 'Apply and verify the existing reviewed repair/Staff migrations before enabling web workflow writes.';
  end if;
end $preflight$;

-- Include the optional mobile location columns and their existing pair rule so
-- this single setup file also covers projects predating the location update.
alter table public.service_concerns
 add column if not exists latitude double precision,
 add column if not exists longitude double precision,
 add column if not exists location_note text;
do $location$
begin
 if not exists(select 1 from pg_constraint where conrelid='public.service_concerns'::regclass
   and conname='service_concerns_location_pair_check') then
  alter table public.service_concerns add constraint service_concerns_location_pair_check check(
   (latitude is null and longitude is null) or
   (latitude is not null and longitude is not null and latitude between -90 and 90 and longitude between -180 and 180));
 end if;
end $location$;

create or replace function public.wd_web_is_staff() returns boolean
language sql stable security invoker set search_path=pg_catalog as $fn$
  select exists(select 1 from public.profiles where user_id=auth.uid() and active and role='staff')
$fn$;
revoke all on function public.wd_web_is_staff() from public, anon;
grant execute on function public.wd_web_is_staff() to authenticated;

-- Resolve the historical-account lookup without a circular RLS dependency
-- between concern INSERT checks and service-account SELECT policies.
create or replace function public.wd_web_staff_account_access(p_account_id uuid) returns boolean
language sql stable security definer set search_path=pg_catalog as $fn$
 select exists(select 1 from public.profiles where user_id=auth.uid() and active and role='staff')
  and exists(select 1 from public.service_accounts a where a.id=p_account_id and
    (a.active or exists(select 1 from public.service_concerns c where c.account_id=a.id)))
$fn$;
revoke all on function public.wd_web_staff_account_access(uuid) from public, anon;
grant execute on function public.wd_web_staff_account_access(uuid) to authenticated;

-- Preserve Admin-only billing/directory/publication; Staff see concerns and their
-- own repair assignments, as in the shared office API.
do $policies$
begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='service_concerns' and policyname='wd_web_staff_concerns_read') then
  create policy wd_web_staff_concerns_read on public.service_concerns for select to authenticated using(public.wd_web_is_staff());
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='service_accounts' and policyname='wd_web_staff_accounts_read') then
  create policy wd_web_staff_accounts_read on public.service_accounts for select to authenticated using(public.wd_web_staff_account_access(id));
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='service_concerns' and policyname='wd_web_office_intake') then
  create policy wd_web_office_intake on public.service_concerns for insert to authenticated with check(
    (public.wd_is_active_admin() or public.wd_web_is_staff()) and submitted_by=auth.uid()
    and exists(select 1 from public.service_accounts a where a.id=service_concerns.account_id and a.active));
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='service_concerns' and policyname='wd_web_staff_review') then
  create policy wd_web_staff_review on public.service_concerns for update to authenticated using(public.wd_web_is_staff())
    with check(public.wd_web_is_staff() and reviewed_by=auth.uid() and reviewed_at is not null);
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='repair_tickets' and policyname='wd_web_staff_tickets_read') then
  create policy wd_web_staff_tickets_read on public.repair_tickets for select to authenticated using(public.wd_web_is_staff() and assigned_to_user_id=auth.uid());
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='repair_tickets' and policyname='wd_web_staff_tickets_update') then
  create policy wd_web_staff_tickets_update on public.repair_tickets for update to authenticated using(public.wd_web_is_staff() and assigned_to_user_id=auth.uid())
    with check(public.wd_web_is_staff() and assigned_to_user_id=auth.uid() and updated_by=auth.uid());
 end if;
end $policies$;

-- Existing column grants and RLS still constrain all writes. The immutable UUID
-- supports retries; the assignee UUID is already validated by wd_ticket_guard.
grant insert(id,latitude,longitude,location_note) on public.service_concerns to authenticated;
grant update(assigned_to_user_id) on public.repair_tickets to authenticated;

create or replace function public.wd_web_workflow(p_action text, p_id uuid, p_version bigint default null, p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path=pg_catalog as $fn$
declare
 actor uuid:=auth.uid(); office_role text; c public.service_concerns%rowtype;
 t public.repair_tickets%rowtype; current_version bigint; note text;
 category text; subject text; description text; location_note text;
 lat double precision; lon double precision;
begin
 select role into office_role from public.profiles where user_id=actor and active;
 if office_role is null or office_role not in ('admin','staff') then
  raise exception 'Active office profile required' using errcode='42501';
 end if;
 if p_id is null then raise exception 'A record identifier is required' using errcode='22023'; end if;
 if p_action='intake' then
  category:=btrim(p_payload->>'category'); subject:=btrim(p_payload->>'subject'); description:=btrim(p_payload->>'description');
  if category is null or category not in ('Water supply','Billing inquiry','Repair request','Other')
    or coalesce(length(subject),0) not between 1 and 150 or coalesce(length(description),0) not between 1 and 3000 then
   raise exception 'Valid category, subject and description required' using errcode='22023';
  end if;
  if (p_payload->>'latitude') is not null or (p_payload->>'longitude') is not null then
   if jsonb_typeof(p_payload->'latitude') is distinct from 'number' or jsonb_typeof(p_payload->'longitude') is distinct from 'number' then
    raise exception 'Choose both coordinates together' using errcode='22023';
   end if;
   lat:=(p_payload->>'latitude')::double precision; lon:=(p_payload->>'longitude')::double precision;
   if not(lat between -90 and 90 and lon between -180 and 180) then raise exception 'Invalid location coordinates' using errcode='22023'; end if;
  end if;
  location_note:=nullif(btrim(p_payload->>'locationNote'),'');
  if length(location_note)>300 or (lat is null and location_note is not null) then raise exception 'Invalid location landmark' using errcode='22023'; end if;
  select * into c from public.service_concerns where id=p_id;
  if found then
   if c.submitted_by is distinct from actor or c.account_id is distinct from (p_payload->>'accountId')::uuid
     or c.category is distinct from category or c.subject is distinct from subject or c.description is distinct from description
     or c.latitude is distinct from lat or c.longitude is distinct from lon or nullif(c.location_note,'') is distinct from location_note then
    raise exception 'Request identifier already saved with different details' using errcode='40001';
   end if;
   return jsonb_build_object('id',c.id);
  end if;
  insert into public.service_concerns(id,account_id,submitted_by,category,subject,description,latitude,longitude,location_note)
   values(p_id,(p_payload->>'accountId')::uuid,actor,category,subject,description,lat,lon,location_note);
  return jsonb_build_object('id',p_id);
 elsif p_action in ('review','dispatch') then
  if p_action='dispatch' and office_role<>'admin' then raise exception 'Administrator required' using errcode='42501'; end if;
  select * into c from public.service_concerns where id=p_id for update;
  if c.id is null then raise exception 'Concern unavailable' using errcode='P0002'; end if;
  select xmin::text::bigint into current_version from public.service_concerns where id=p_id;
  if p_version is null or p_version=0 or current_version<>p_version then raise exception 'Record changed; reload before saving' using errcode='40001'; end if;
  if p_action='review' then
   if c.status in ('Closed','Resolved') or exists(select 1 from public.repair_tickets where concern_id=p_id) then
    raise exception 'Use ticket processing for linked or completed concerns' using errcode='40001';
   end if;
   if (p_payload->>'status') is null or (p_payload->>'status') not in ('Under review','Closed')
      or length(p_payload->>'response')>3000 or ((p_payload->>'status')='Closed' and coalesce(length(btrim(p_payload->>'response')),0)=0) then
    raise exception 'Valid review decision and closure response required' using errcode='22023';
   end if;
   update public.service_concerns set status=p_payload->>'status',admin_response=nullif(btrim(p_payload->>'response'),''),reviewed_by=actor,reviewed_at=clock_timestamp() where id=p_id;
   return jsonb_build_object('id',p_id);
  end if;
  note:=btrim(p_payload->>'note');
  if coalesce(length(note),0) not between 1 and 3000 then raise exception 'Ticket note required' using errcode='22023'; end if;
  if c.status<>'Under review' or c.reviewed_by is null or c.reviewed_at is null or exists(select 1 from public.repair_tickets where concern_id=p_id) then
   raise exception 'A reviewed concern without a ticket is required' using errcode='40001';
  end if;
  insert into public.repair_tickets(concern_id,status,latest_update,created_by,updated_by)
   values(p_id,'Open',note,actor,actor) returning id into p_id;
  return jsonb_build_object('id',p_id);
 elsif p_action='update_ticket' then
  select * into t from public.repair_tickets where id=p_id for update;
  if t.id is null then raise exception 'Ticket unavailable or not assigned to you' using errcode='P0002'; end if;
  select xmin::text::bigint into current_version from public.repair_tickets where id=p_id;
  if p_version is null or p_version=0 or current_version<>p_version then raise exception 'Record changed; reload before saving' using errcode='40001'; end if;
  note:=btrim(p_payload->>'note');
  if coalesce(length(note),0) not between 1 and 3000 then raise exception 'Update note required' using errcode='22023'; end if;
  update public.repair_tickets set status=p_payload->>'status',assigned_to_user_id=(p_payload->>'assignedToUserId')::uuid,
    latest_update=note,updated_by=actor where id=p_id;
  return jsonb_build_object('id',p_id);
 end if;
 raise exception 'Unsupported workflow operation' using errcode='22023';
end $fn$;

-- Scoped history names are safe even when Staff cannot browse other profiles.
create or replace function public.wd_web_ticket_history(p_ticket_id uuid) returns jsonb
language plpgsql stable security definer set search_path=pg_catalog as $fn$
begin
 if not exists(select 1 from public.profiles where user_id=auth.uid() and active and role in ('admin','staff'))
   or not public.wd_can_read_ticket(p_ticket_id) then raise exception 'Ticket unavailable' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',h.id,'status',h.status,'note',h.note,'changedBy',p.display_name,
    'assignedTo',h.assigned_to,'changedAt',h.changed_at) order by h.id),'[]'::jsonb)
    from public.ticket_status_history h join public.profiles p on p.user_id=h.changed_by where h.ticket_id=p_ticket_id);
end $fn$;

revoke all on function public.wd_web_workflow(text,uuid,bigint,jsonb),public.wd_web_ticket_history(uuid) from public, anon;
grant execute on function public.wd_web_workflow(text,uuid,bigint,jsonb),public.wd_web_ticket_history(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
