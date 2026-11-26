-- Run in Supabase SQL Editor and copy the submission_diagnostics result.
-- Read-only: this does not change accounts, permissions, policies, or concerns.
select jsonb_pretty(jsonb_build_object(
  'table_permissions', jsonb_build_object(
    'authenticated_select', has_table_privilege('authenticated', 'public.service_concerns', 'SELECT'),
    'authenticated_insert', has_table_privilege('authenticated', 'public.service_concerns', 'INSERT'),
    'authenticated_update', has_table_privilege('authenticated', 'public.service_concerns', 'UPDATE'),
    'rls_enabled', (select relrowsecurity from pg_class where oid = 'public.service_concerns'::regclass)
  ),
  'columns', (
    select jsonb_agg(jsonb_build_object(
      'name', a.attname,
      'required', a.attnotnull,
      'default', pg_get_expr(d.adbin, d.adrelid),
      'can_select', has_column_privilege('authenticated', a.attrelid, a.attnum, 'SELECT'),
      'can_insert', has_column_privilege('authenticated', a.attrelid, a.attnum, 'INSERT'),
      'can_update', has_column_privilege('authenticated', a.attrelid, a.attnum, 'UPDATE')
    ) order by a.attnum)
    from pg_attribute a
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid = 'public.service_concerns'::regclass
      and a.attnum > 0 and not a.attisdropped
  ),
  'policies', (
    select jsonb_agg(to_jsonb(p)) from (
      select tablename, policyname, roles, cmd, qual, with_check
      from pg_policies
      where schemaname = 'public'
        and tablename in ('service_concerns', 'profiles', 'account_access', 'service_accounts')
      order by tablename, policyname
    ) p
  ),
  'policy_functions', (
    select jsonb_agg(jsonb_build_object('name', f.oid::regprocedure::text,
                                      'definition', pg_get_functiondef(f.oid)))
    from pg_proc f
    join pg_namespace n on n.oid = f.pronamespace
    where n.nspname = 'public' and f.oid in (
      select dep.refobjid from pg_depend dep
      join pg_policy pol on dep.classid = 'pg_policy'::regclass and dep.objid = pol.oid
      where dep.refclassid = 'pg_proc'::regclass
        and pol.polrelid in ('public.service_concerns'::regclass,
                            'public.account_access'::regclass,
                            'public.profiles'::regclass,
                            'public.service_accounts'::regclass)
    )
  ),
  'concern_triggers', (
    select jsonb_agg(jsonb_build_object(
      'name', t.tgname,
      'trigger', pg_get_triggerdef(t.oid),
      'function', pg_get_functiondef(t.tgfoid)
    )) from pg_trigger t
    where t.tgrelid = 'public.service_concerns'::regclass and not t.tgisinternal
  ),
  'client_account_status', (
    select jsonb_agg(jsonb_build_object(
      'display_name', p.display_name,
      'profile_active', p.active,
      'account_number', s.account_number,
      'account_active', s.active,
      'link_active', a.active,
      'relationship', a.relationship,
      'has_authorization_reference', nullif(trim(a.authorization_reference), '') is not null,
      'has_verifier', a.verified_by is not null,
      'verified_at', a.verified_at,
      'revoked_at', a.revoked_at
    ) order by p.display_name, s.account_number)
    from public.profiles p
    left join public.account_access a on a.user_id = p.user_id
    left join public.service_accounts s on s.id = a.account_id
    where p.role = 'client'
  )
)) as submission_diagnostics;
