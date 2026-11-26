-- Run in Supabase SQL Editor if the location columns already exist but
-- submitting a concern returns access denied. Safe to run more than once.
-- Keep the existing RLS policies and all other column permissions unchanged.
grant insert (latitude, longitude, location_note)
  on table public.service_concerns to authenticated;

-- All three can_insert values should now be true.
select column_name,
       has_column_privilege(
         'authenticated', 'public.service_concerns', column_name, 'INSERT'
       ) as can_insert
from information_schema.columns
where table_schema = 'public' and table_name = 'service_concerns'
  and column_name in ('latitude', 'longitude', 'location_note')
order by ordinal_position;
