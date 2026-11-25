-- Only for an explicitly selected, empty LOCAL development/test database.
-- Reconstructs the consumer source contract; it is NOT a Supabase schema dump.
CREATE SCHEMA IF NOT EXISTS auth;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF; END $$;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.sub',true),''),
 NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid $$;
CREATE TABLE public.profiles (
 user_id uuid PRIMARY KEY, display_name text NOT NULL, role text NOT NULL CHECK(role IN ('admin','staff','client')), active boolean NOT NULL DEFAULT true);
CREATE TABLE public.service_accounts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), account_number text NOT NULL UNIQUE,
 holder_name text NOT NULL, service_address text NOT NULL, active boolean NOT NULL DEFAULT true, updated_by uuid REFERENCES public.profiles(user_id));
CREATE TABLE public.account_access (
 user_id uuid NOT NULL REFERENCES public.profiles(user_id), account_id uuid NOT NULL REFERENCES public.service_accounts(id),
 active boolean NOT NULL DEFAULT true, PRIMARY KEY(user_id,account_id));
CREATE UNIQUE INDEX uq_active_account_access ON public.account_access(user_id) WHERE active;
CREATE TABLE public.service_concerns (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), account_id uuid NOT NULL REFERENCES public.service_accounts(id),
 submitted_by uuid NOT NULL REFERENCES public.profiles(user_id), category text NOT NULL, subject text NOT NULL, description text NOT NULL,
 status text NOT NULL DEFAULT 'Submitted' CHECK(status IN ('Submitted','Under review','Resolved','Closed')),
 admin_response text, reviewed_by uuid REFERENCES public.profiles(user_id), reviewed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.repair_tickets (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), concern_id uuid NOT NULL UNIQUE REFERENCES public.service_concerns(id),
 assigned_to text, status text NOT NULL DEFAULT 'Open' CHECK(status IN ('Open','Assigned','In progress','Resolved')),
 latest_update text NOT NULL, created_by uuid NOT NULL REFERENCES public.profiles(user_id),
 updated_by uuid NOT NULL REFERENCES public.profiles(user_id), updated_at timestamptz NOT NULL DEFAULT now());
-- Local RLS reproduces ownership boundaries for integration tests, not unknown production policies.
CREATE FUNCTION public.wd_test_office() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM public.profiles WHERE user_id=auth.uid() AND active AND role IN ('admin','staff')) $$;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY profile_read ON public.profiles FOR SELECT TO authenticated USING(user_id=auth.uid() OR public.wd_test_office());
ALTER TABLE public.service_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY accounts_read ON public.service_accounts FOR SELECT TO authenticated USING(public.wd_test_office() OR EXISTS(
 SELECT 1 FROM public.account_access a WHERE a.account_id=id AND a.user_id=auth.uid() AND a.active));
ALTER TABLE public.account_access ENABLE ROW LEVEL SECURITY;
CREATE POLICY access_read ON public.account_access FOR SELECT TO authenticated USING(user_id=auth.uid() OR public.wd_test_office());
ALTER TABLE public.service_concerns ENABLE ROW LEVEL SECURITY;
CREATE POLICY concern_read ON public.service_concerns FOR SELECT TO authenticated USING(public.wd_test_office() OR EXISTS(
 SELECT 1 FROM public.account_access a WHERE a.account_id=service_concerns.account_id AND a.user_id=auth.uid() AND a.active));
CREATE POLICY concern_insert ON public.service_concerns FOR INSERT TO authenticated WITH CHECK(submitted_by=auth.uid() AND EXISTS(
 SELECT 1 FROM public.account_access a WHERE a.account_id=service_concerns.account_id AND a.user_id=auth.uid() AND a.active));
ALTER TABLE public.repair_tickets ENABLE ROW LEVEL SECURITY;
CREATE POLICY ticket_read ON public.repair_tickets FOR SELECT TO authenticated USING(EXISTS(
 SELECT 1 FROM public.service_concerns c WHERE c.id=concern_id));
GRANT USAGE ON SCHEMA public,auth TO authenticated;
GRANT SELECT ON public.profiles, public.service_accounts, public.account_access, public.service_concerns, public.repair_tickets TO authenticated;
GRANT INSERT ON public.service_concerns TO authenticated;
