-- Run after staff-role.sql. Existing tickets and audit history are retained.
begin;
do $$ begin
  if to_regprocedure('public.wd_staff_access(uuid,boolean)') is null then
    raise exception 'Apply staff-role.sql before enabling direct repair resolution.';
  end if;
end $$;
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
 IF NOT COALESCE(((OLD.status='Open' AND NEW.status IN ('Open','Assigned')) OR (OLD.status='Assigned' AND NEW.status IN ('Assigned','In progress','Resolved')) OR
 (OLD.status='In progress' AND NEW.status IN ('In progress','Completed','Resolved')) OR (OLD.status='Completed' AND NEW.status IN ('Completed','In progress','Resolved'))),false) THEN RAISE EXCEPTION 'Invalid ticket transition' USING ERRCODE='23514'; END IF;
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

notify pgrst,'reload schema';
commit;
