-- Read-only: inspect required link fields and allowed relationship values.
select jsonb_build_object(
  'columns', (
    select jsonb_agg(jsonb_build_object(
      'name', a.attname,
      'type', format_type(a.atttypid, a.atttypmod),
      'required', a.attnotnull,
      'default', pg_get_expr(d.adbin, d.adrelid)
    ) order by a.attnum)
    from pg_attribute a
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid = 'public.account_access'::regclass
      and a.attnum > 0 and not a.attisdropped
  ),
  'constraints', (
    select jsonb_agg(pg_get_constraintdef(c.oid))
    from pg_constraint c
    where c.conrelid = 'public.account_access'::regclass
  ),
  'relationship_enum_values', (
    select jsonb_agg(e.enumlabel order by e.enumsortorder)
    from pg_attribute a join pg_enum e on e.enumtypid = a.atttypid
    where a.attrelid = 'public.account_access'::regclass
      and a.attname = 'relationship'
  ),
  'existing_relationship_values', (
    select jsonb_agg(r.relationship)
    from (select distinct relationship from public.account_access) r
  )
) as account_access_schema;
