DO $guard$
DECLARE r record; actual text;
BEGIN
 FOR r IN SELECT * FROM (VALUES
 ('profiles','user_id','uuid'),('profiles','role','text'),('profiles','active','bool'),('profiles','display_name','text'),
 ('service_accounts','id','uuid'),('service_accounts','account_number','text'),('service_accounts','holder_name','text'),('service_accounts','service_address','text'),('service_accounts','active','bool'),
 ('account_access','user_id','uuid'),('account_access','account_id','uuid'),('account_access','active','bool'),
 ('service_concerns','id','uuid'),('service_concerns','account_id','uuid'),('service_concerns','submitted_by','uuid'),
 ('service_concerns','category','text'),('service_concerns','subject','text'),('service_concerns','description','text'),('service_concerns','status','text'),
 ('service_concerns','admin_response','text'),('service_concerns','reviewed_by','uuid'),('service_concerns','reviewed_at','timestamptz'),('service_concerns','created_at','timestamptz'),
 ('repair_tickets','id','uuid'),('repair_tickets','concern_id','uuid'),('repair_tickets','assigned_to','text'),('repair_tickets','status','text'),
 ('repair_tickets','latest_update','text'),('repair_tickets','created_by','uuid'),('repair_tickets','updated_by','uuid'),('repair_tickets','updated_at','timestamptz')
 ) AS expected(tab,col,typ) LOOP
 SELECT udt_name INTO actual FROM information_schema.columns WHERE table_schema='public' AND table_name=r.tab AND column_name=r.col;
 IF actual IS NULL OR NOT(actual=r.typ OR (r.typ='text' AND actual='varchar')) THEN
 RAISE EXCEPTION 'Schema review required: %.% expected %, found %',r.tab,r.col,r.typ,COALESCE(actual,'missing'); END IF;
 END LOOP;
 IF to_regclass('public.ticket_status_history') IS NOT NULL THEN RAISE EXCEPTION 'Existing ticket history needs reconciliation before adopting this migration.'; END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relname IN ('repair_tickets','service_concerns') AND NOT t.tgisinternal) THEN
 RAISE EXCEPTION 'Existing workflow triggers need review before applying this migration.'; END IF;
 IF EXISTS(SELECT 1 FROM public.repair_tickets GROUP BY concern_id HAVING count(*)>1) THEN
 RAISE EXCEPTION 'Duplicate tickets must be reconciled before this migration.'; END IF;
END $guard$;
ALTER TABLE public.service_concerns ADD COLUMN repair_dispatched_at timestamptz;
ALTER TABLE public.repair_tickets ADD COLUMN assigned_to_user_id uuid REFERENCES public.profiles(user_id);
CREATE UNIQUE INDEX IF NOT EXISTS wd_one_ticket_per_concern ON public.repair_tickets(concern_id);
