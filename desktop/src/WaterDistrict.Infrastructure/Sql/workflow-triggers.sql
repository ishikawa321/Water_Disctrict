-- One truthful upgrade snapshot; previous unrecorded events are not invented.
UPDATE public.repair_tickets t SET assigned_to_user_id=(SELECT min(p.user_id::text)::uuid FROM public.profiles p
 WHERE p.active AND p.role='staff' AND p.display_name=t.assigned_to HAVING count(*)=1) WHERE assigned_to IS NOT NULL;
INSERT INTO public.ticket_status_history(ticket_id,changed_by,status,note,assigned_to_user_id,assigned_to,changed_at)
 SELECT id,COALESCE(updated_by,created_by),status,'Existing ticket state captured during upgrade; earlier history is unavailable.',
 assigned_to_user_id,assigned_to,updated_at FROM public.repair_tickets;
UPDATE public.service_concerns c SET repair_dispatched_at=t.updated_at FROM public.repair_tickets t WHERE t.concern_id=c.id;
CREATE FUNCTION public.wd_actor() RETURNS uuid LANGUAGE sql STABLE SET search_path=pg_catalog AS $fn$
 SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.sub',true),''),
 NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid $fn$;
CREATE FUNCTION public.wd_concern_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE actor uuid:=public.wd_actor(); office_role text;
BEGIN
 SELECT role INTO office_role FROM public.profiles WHERE user_id=actor AND active FOR SHARE;
 IF office_role IS NULL THEN RAISE EXCEPTION 'Active profile required' USING ERRCODE='42501'; END IF;
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Retain operational concerns' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.service_accounts WHERE id=NEW.account_id AND active) THEN RAISE EXCEPTION 'Active account required' USING ERRCODE='23514'; END IF;
 IF COALESCE(length(btrim(NEW.category)),0) NOT BETWEEN 1 AND 80 OR COALESCE(length(btrim(NEW.subject)),0) NOT BETWEEN 1 AND 160
 OR COALESCE(length(btrim(NEW.description)),0) NOT BETWEEN 1 AND 3000 OR COALESCE(length(NEW.admin_response),0)>3000 THEN
 RAISE EXCEPTION 'Invalid concern information' USING ERRCODE='23514'; END IF;
 IF TG_OP='INSERT' THEN
 IF office_role NOT IN ('admin','staff') AND NOT(office_role='client' AND EXISTS(SELECT 1 FROM public.account_access
 WHERE user_id=actor AND account_id=NEW.account_id AND active)) THEN RAISE EXCEPTION 'Account access required' USING ERRCODE='42501'; END IF;
 NEW.submitted_by:=actor; NEW.created_at:=clock_timestamp(); NEW.status:='Submitted';
 NEW.reviewed_by:=NULL; NEW.reviewed_at:=NULL; NEW.admin_response:=NULL; NEW.repair_dispatched_at:=NULL; RETURN NEW;
 END IF;
 IF office_role NOT IN ('admin','staff') THEN RAISE EXCEPTION 'Office access required' USING ERRCODE='42501'; END IF;
 IF NEW.id<>OLD.id OR NEW.account_id<>OLD.account_id OR NEW.submitted_by<>OLD.submitted_by OR NEW.created_at<>OLD.created_at
 OR NEW.category<>OLD.category OR NEW.subject<>OLD.subject OR NEW.description<>OLD.description THEN
 RAISE EXCEPTION 'Original concern details are immutable' USING ERRCODE='23514'; END IF;
 IF pg_trigger_depth()=1 THEN
 IF OLD.status IN ('Resolved','Closed') OR EXISTS(SELECT 1 FROM public.repair_tickets WHERE concern_id=OLD.id) THEN
 RAISE EXCEPTION 'Use ticket processing for linked or completed concerns' USING ERRCODE='23514'; END IF;
 IF NEW.status IS NULL OR NEW.status NOT IN ('Under review','Closed') OR (NEW.status='Closed' AND COALESCE(length(btrim(NEW.admin_response)),0)=0) THEN
 RAISE EXCEPTION 'Review decision and closure response required' USING ERRCODE='23514'; END IF;
 NEW.repair_dispatched_at:=OLD.repair_dispatched_at; NEW.reviewed_by:=actor; NEW.reviewed_at:=clock_timestamp();
 END IF; RETURN NEW;
END $fn$;
CREATE TRIGGER wd_concern_guard BEFORE INSERT OR UPDATE OR DELETE ON public.service_concerns FOR EACH ROW EXECUTE FUNCTION public.wd_concern_guard();
CREATE FUNCTION public.wd_ticket_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
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
 IF NOT COALESCE(((OLD.status='Open' AND NEW.status IN ('Open','Assigned')) OR (OLD.status='Assigned' AND NEW.status IN ('Assigned','In progress')) OR
 (OLD.status='In progress' AND NEW.status IN ('In progress','Resolved'))),false) THEN RAISE EXCEPTION 'Invalid ticket transition' USING ERRCODE='23514'; END IF;
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
CREATE TRIGGER wd_ticket_guard BEFORE INSERT OR UPDATE OR DELETE ON public.repair_tickets FOR EACH ROW EXECUTE FUNCTION public.wd_ticket_guard();
CREATE FUNCTION public.wd_ticket_event() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
BEGIN
 INSERT INTO public.ticket_status_history(ticket_id,changed_by,status,note,assigned_to_user_id,assigned_to,changed_at)
 VALUES(NEW.id,public.wd_actor(),NEW.status,NEW.latest_update,NEW.assigned_to_user_id,NEW.assigned_to,NEW.updated_at);
 IF TG_OP='INSERT' THEN UPDATE public.service_concerns SET repair_dispatched_at=NEW.updated_at WHERE id=NEW.concern_id;
 ELSIF NEW.status='Resolved' THEN UPDATE public.service_concerns SET status='Resolved',admin_response=NEW.latest_update,
 reviewed_by=public.wd_actor(),reviewed_at=NEW.updated_at WHERE id=NEW.concern_id; END IF; RETURN NEW;
END $fn$;
CREATE TRIGGER wd_ticket_event AFTER INSERT OR UPDATE ON public.repair_tickets FOR EACH ROW EXECUTE FUNCTION public.wd_ticket_event();
CREATE FUNCTION public.wd_history_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN RAISE EXCEPTION 'Ticket history is append-only' USING ERRCODE='42501'; END $fn$;
CREATE TRIGGER wd_history_guard BEFORE UPDATE OR DELETE ON public.ticket_status_history FOR EACH ROW EXECUTE FUNCTION public.wd_history_guard();
CREATE FUNCTION public.wd_can_read_ticket(ticket_uuid uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.profiles p JOIN public.repair_tickets t ON t.id=ticket_uuid JOIN public.service_concerns c ON c.id=t.concern_id
 WHERE p.user_id=public.wd_actor() AND p.active AND (p.role='admin' OR (p.role='staff' AND t.assigned_to_user_id=p.user_id) OR
 (p.role='client' AND EXISTS(SELECT 1 FROM public.account_access a WHERE a.user_id=p.user_id AND a.account_id=c.account_id AND a.active)))) $fn$;
ALTER TABLE public.ticket_status_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY wd_history_read ON public.ticket_status_history FOR SELECT USING(public.wd_can_read_ticket(ticket_id));
REVOKE ALL ON public.ticket_status_history FROM PUBLIC;
REVOKE ALL ON FUNCTION public.wd_ticket_guard(),public.wd_ticket_event(),public.wd_concern_guard(),public.wd_history_guard() FROM PUBLIC;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN REVOKE ALL ON public.ticket_status_history FROM authenticated; GRANT SELECT ON public.ticket_status_history TO authenticated; END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN REVOKE ALL ON public.ticket_status_history FROM anon; END IF; END $$;
