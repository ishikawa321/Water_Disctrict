-- Run in Supabase SQL Editor. Existing concerns retain an empty location.
begin;
alter table public.service_concerns
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists location_note text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.service_concerns'::regclass
      and conname = 'service_concerns_location_pair_check'
  ) then
    alter table public.service_concerns
      add constraint service_concerns_location_pair_check check (
        (latitude is null and longitude is null)
        or (latitude is not null and longitude is not null
          and latitude between -90 and 90
          and longitude between -180 and 180)
      );
  end if;
end $$;

-- The existing schema grants INSERT per column. New columns need their own
-- grant; the existing client/account INSERT policy still controls row access.
grant insert (latitude, longitude, location_note)
  on table public.service_concerns to authenticated;
commit;
