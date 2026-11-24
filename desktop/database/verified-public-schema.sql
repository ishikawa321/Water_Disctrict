-- Schema-only export verified on 2026-11-25. No production row data.
-- Auth users/uid and service roles are supplied by Supabase, or local test stubs.
--
-- PostgreSQL database dump
--


-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.12

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rls_auto_enable() RETURNS event_trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
  tbl name;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
        EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account_access; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.account_access (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_id uuid NOT NULL,
    user_id uuid NOT NULL,
    relationship text NOT NULL,
    authorization_reference text NOT NULL,
    verified_by uuid NOT NULL,
    verified_at timestamp with time zone DEFAULT now() NOT NULL,
    active boolean DEFAULT true NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT account_access_authorization_reference_check CHECK ((length(TRIM(BOTH FROM authorization_reference)) > 0)),
    CONSTRAINT account_access_check CHECK (((active AND (revoked_at IS NULL)) OR ((NOT active) AND (revoked_at IS NOT NULL)))),
    CONSTRAINT account_access_relationship_check CHECK ((relationship = ANY (ARRAY['holder'::text, 'representative'::text])))
);


--
-- Name: announcements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.announcements (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    message text NOT NULL,
    published boolean DEFAULT false NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT announcements_message_check CHECK (((length(TRIM(BOTH FROM message)) >= 1) AND (length(TRIM(BOTH FROM message)) <= 5000))),
    CONSTRAINT announcements_title_check CHECK (((length(TRIM(BOTH FROM title)) >= 1) AND (length(TRIM(BOTH FROM title)) <= 150)))
);


--
-- Name: bills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bills (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_id uuid NOT NULL,
    bill_number text NOT NULL,
    billing_period_start date NOT NULL,
    billing_period_end date NOT NULL,
    due_date date NOT NULL,
    amount_due numeric(12,2) NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT bills_amount_due_check CHECK ((amount_due >= (0)::numeric)),
    CONSTRAINT bills_bill_number_check CHECK ((length(TRIM(BOTH FROM bill_number)) > 0)),
    CONSTRAINT bills_check CHECK ((billing_period_end >= billing_period_start))
);


--
-- Name: offline_payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.offline_payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bill_id uuid NOT NULL,
    receipt_reference text NOT NULL,
    payment_date date NOT NULL,
    amount_paid numeric(12,2) NOT NULL,
    verified_by uuid NOT NULL,
    verified_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT offline_payments_amount_paid_check CHECK ((amount_paid > (0)::numeric)),
    CONSTRAINT offline_payments_receipt_reference_check CHECK ((length(TRIM(BOTH FROM receipt_reference)) > 0))
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    user_id uuid NOT NULL,
    display_name text NOT NULL,
    role text DEFAULT 'client'::text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT profiles_display_name_check CHECK ((length(TRIM(BOTH FROM display_name)) > 0)),
    CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['client'::text, 'admin'::text])))
);


--
-- Name: repair_tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.repair_tickets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    concern_id uuid NOT NULL,
    assigned_to text,
    status text DEFAULT 'Open'::text NOT NULL,
    latest_update text NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT repair_tickets_assigned_to_check CHECK (((length(TRIM(BOTH FROM assigned_to)) >= 1) AND (length(TRIM(BOTH FROM assigned_to)) <= 150))),
    CONSTRAINT repair_tickets_check CHECK (((status <> ALL (ARRAY['Assigned'::text, 'In progress'::text])) OR (assigned_to IS NOT NULL))),
    CONSTRAINT repair_tickets_latest_update_check CHECK (((length(TRIM(BOTH FROM latest_update)) >= 1) AND (length(TRIM(BOTH FROM latest_update)) <= 3000))),
    CONSTRAINT repair_tickets_status_check CHECK ((status = ANY (ARRAY['Open'::text, 'Assigned'::text, 'In progress'::text, 'Resolved'::text])))
);


--
-- Name: service_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_number text NOT NULL,
    holder_name text NOT NULL,
    service_address text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT service_accounts_account_number_check CHECK ((length(TRIM(BOTH FROM account_number)) > 0))
);


--
-- Name: service_concerns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_concerns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_id uuid NOT NULL,
    submitted_by uuid NOT NULL,
    category text NOT NULL,
    subject text NOT NULL,
    description text NOT NULL,
    status text DEFAULT 'Submitted'::text NOT NULL,
    admin_response text,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    latitude double precision,
    longitude double precision,
    location_note text,
    CONSTRAINT service_concerns_admin_response_check CHECK ((length(admin_response) <= 3000)),
    CONSTRAINT service_concerns_category_check CHECK ((category = ANY (ARRAY['Water supply'::text, 'Billing inquiry'::text, 'Repair request'::text, 'Other'::text]))),
    CONSTRAINT service_concerns_description_check CHECK (((length(TRIM(BOTH FROM description)) >= 1) AND (length(TRIM(BOTH FROM description)) <= 3000))),
    CONSTRAINT service_concerns_status_check CHECK ((status = ANY (ARRAY['Submitted'::text, 'Under review'::text, 'Resolved'::text, 'Closed'::text]))),
    CONSTRAINT service_concerns_subject_check CHECK (((length(TRIM(BOTH FROM subject)) >= 1) AND (length(TRIM(BOTH FROM subject)) <= 150)))
);


--
-- Name: account_access account_access_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_access
    ADD CONSTRAINT account_access_pkey PRIMARY KEY (id);


--
-- Name: announcements announcements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_pkey PRIMARY KEY (id);


--
-- Name: bills bills_bill_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_bill_number_key UNIQUE (bill_number);


--
-- Name: bills bills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_pkey PRIMARY KEY (id);


--
-- Name: offline_payments offline_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offline_payments
    ADD CONSTRAINT offline_payments_pkey PRIMARY KEY (id);


--
-- Name: offline_payments offline_payments_receipt_reference_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offline_payments
    ADD CONSTRAINT offline_payments_receipt_reference_key UNIQUE (receipt_reference);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (user_id);


--
-- Name: repair_tickets repair_tickets_concern_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_tickets
    ADD CONSTRAINT repair_tickets_concern_id_key UNIQUE (concern_id);


--
-- Name: repair_tickets repair_tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_tickets
    ADD CONSTRAINT repair_tickets_pkey PRIMARY KEY (id);


--
-- Name: service_accounts service_accounts_account_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_accounts
    ADD CONSTRAINT service_accounts_account_number_key UNIQUE (account_number);


--
-- Name: service_accounts service_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_accounts
    ADD CONSTRAINT service_accounts_pkey PRIMARY KEY (id);


--
-- Name: service_concerns service_concerns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_concerns
    ADD CONSTRAINT service_concerns_pkey PRIMARY KEY (id);


--
-- Name: bills_account_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bills_account_id_idx ON public.bills USING btree (account_id);


--
-- Name: offline_payments_bill_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX offline_payments_bill_id_idx ON public.offline_payments USING btree (bill_id);


--
-- Name: one_active_account_per_login; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_account_per_login ON public.account_access USING btree (user_id) WHERE (active = true);


--
-- Name: one_active_login_per_account; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_login_per_account ON public.account_access USING btree (account_id) WHERE (active = true);


--
-- Name: service_concerns_account_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX service_concerns_account_id_idx ON public.service_concerns USING btree (account_id);


--
-- Name: account_access account_access_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_access
    ADD CONSTRAINT account_access_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.service_accounts(id) ON DELETE RESTRICT;


--
-- Name: account_access account_access_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_access
    ADD CONSTRAINT account_access_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(user_id) ON DELETE RESTRICT;


--
-- Name: account_access account_access_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.account_access
    ADD CONSTRAINT account_access_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES public.profiles(user_id) ON DELETE RESTRICT;


--
-- Name: announcements announcements_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(user_id) ON DELETE RESTRICT;


--
-- Name: announcements announcements_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(user_id) ON DELETE RESTRICT;


--
-- Name: bills bills_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.service_accounts(id) ON DELETE RESTRICT;


--
-- Name: bills bills_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(user_id) ON DELETE RESTRICT;


--
-- Name: offline_payments offline_payments_bill_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offline_payments
    ADD CONSTRAINT offline_payments_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES public.bills(id) ON DELETE RESTRICT;


--
-- Name: offline_payments offline_payments_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offline_payments
    ADD CONSTRAINT offline_payments_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES public.profiles(user_id) ON DELETE RESTRICT;


--
-- Name: profiles profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;


--
-- Name: repair_tickets repair_tickets_concern_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_tickets
    ADD CONSTRAINT repair_tickets_concern_id_fkey FOREIGN KEY (concern_id) REFERENCES public.service_concerns(id) ON DELETE RESTRICT;


--
-- Name: repair_tickets repair_tickets_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_tickets
    ADD CONSTRAINT repair_tickets_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(user_id) ON DELETE RESTRICT;


--
-- Name: repair_tickets repair_tickets_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.repair_tickets
    ADD CONSTRAINT repair_tickets_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(user_id) ON DELETE RESTRICT;


--
-- Name: service_accounts service_accounts_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_accounts
    ADD CONSTRAINT service_accounts_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(user_id);


--
-- Name: service_concerns service_concerns_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_concerns
    ADD CONSTRAINT service_concerns_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.service_accounts(id) ON DELETE RESTRICT;


--
-- Name: service_concerns service_concerns_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_concerns
    ADD CONSTRAINT service_concerns_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.profiles(user_id) ON DELETE RESTRICT;


--
-- Name: service_concerns service_concerns_submitted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_concerns
    ADD CONSTRAINT service_concerns_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES public.profiles(user_id) ON DELETE RESTRICT;


--
-- Name: bills Active administrators can add bills; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Active administrators can add bills" ON public.bills FOR INSERT TO authenticated WITH CHECK (((created_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true))))));


--
-- Name: service_accounts Active administrators can create service accounts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Active administrators can create service accounts" ON public.service_accounts FOR INSERT TO authenticated WITH CHECK (((updated_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.user_id = ( SELECT auth.uid() AS uid)) AND (profiles.role = 'admin'::text) AND (profiles.active = true))))));


--
-- Name: bills Active administrators can read bills; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Active administrators can read bills" ON public.bills FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true)))));


--
-- Name: service_accounts Active administrators can update service accounts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Active administrators can update service accounts" ON public.service_accounts FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.user_id = ( SELECT auth.uid() AS uid)) AND (profiles.role = 'admin'::text) AND (profiles.active = true))))) WITH CHECK (((updated_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.user_id = ( SELECT auth.uid() AS uid)) AND (profiles.role = 'admin'::text) AND (profiles.active = true))))));


--
-- Name: service_accounts Active administrators can view service accounts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Active administrators can view service accounts" ON public.service_accounts FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.user_id = ( SELECT auth.uid() AS uid)) AND (profiles.role = 'admin'::text) AND (profiles.active = true)))));


--
-- Name: announcements Administrators can create announcements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Administrators can create announcements" ON public.announcements FOR INSERT TO authenticated WITH CHECK (((created_by = ( SELECT auth.uid() AS uid)) AND (updated_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true))))));


--
-- Name: repair_tickets Administrators can create repair tickets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Administrators can create repair tickets" ON public.repair_tickets FOR INSERT TO authenticated WITH CHECK (((created_by = ( SELECT auth.uid() AS uid)) AND (updated_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true))))));


--
-- Name: announcements Administrators can read all announcements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Administrators can read all announcements" ON public.announcements FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true)))));


--
-- Name: service_concerns Administrators can read concerns; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Administrators can read concerns" ON public.service_concerns FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true)))));


--
-- Name: repair_tickets Administrators can read repair tickets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Administrators can read repair tickets" ON public.repair_tickets FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true)))));


--
-- Name: offline_payments Administrators can read verified payments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Administrators can read verified payments" ON public.offline_payments FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true)))));


--
-- Name: offline_payments Administrators can record verified payments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Administrators can record verified payments" ON public.offline_payments FOR INSERT TO authenticated WITH CHECK (((verified_by = ( SELECT auth.uid() AS uid)) AND (payment_date <= CURRENT_DATE) AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true))))));


--
-- Name: service_concerns Administrators can review concerns; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Administrators can review concerns" ON public.service_concerns FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true))))) WITH CHECK (((reviewed_by = ( SELECT auth.uid() AS uid)) AND (reviewed_at IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true))))));


--
-- Name: announcements Administrators can update announcements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Administrators can update announcements" ON public.announcements FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true))))) WITH CHECK (((updated_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true))))));


--
-- Name: repair_tickets Administrators can update repair tickets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Administrators can update repair tickets" ON public.repair_tickets FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true))))) WITH CHECK (((updated_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'admin'::text) AND (p.active = true))))));


--
-- Name: bills Clients can read bills for their linked account; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clients can read bills for their linked account" ON public.bills FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.account_access a
  WHERE ((a.account_id = bills.account_id) AND (a.user_id = ( SELECT auth.uid() AS uid)) AND (a.active = true)))));


--
-- Name: announcements Clients can read published announcements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clients can read published announcements" ON public.announcements FOR SELECT TO authenticated USING (((published = true) AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'client'::text) AND (p.active = true))))));


--
-- Name: service_concerns Clients can read their account concerns; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clients can read their account concerns" ON public.service_concerns FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM (public.account_access a
     JOIN public.profiles p ON ((p.user_id = a.user_id)))
  WHERE ((a.account_id = service_concerns.account_id) AND (a.user_id = ( SELECT auth.uid() AS uid)) AND (a.active = true) AND (p.role = 'client'::text) AND (p.active = true)))));


--
-- Name: repair_tickets Clients can read their account repair tickets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clients can read their account repair tickets" ON public.repair_tickets FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM ((public.service_concerns c
     JOIN public.account_access a ON ((a.account_id = c.account_id)))
     JOIN public.profiles p ON ((p.user_id = a.user_id)))
  WHERE ((c.id = repair_tickets.concern_id) AND (a.user_id = ( SELECT auth.uid() AS uid)) AND (a.active = true) AND (p.role = 'client'::text) AND (p.active = true)))));


--
-- Name: offline_payments Clients can read their linked account payments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clients can read their linked account payments" ON public.offline_payments FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM (public.bills b
     JOIN public.account_access a ON ((a.account_id = b.account_id)))
  WHERE ((b.id = offline_payments.bill_id) AND (a.user_id = ( SELECT auth.uid() AS uid)) AND (a.active = true) AND (EXISTS ( SELECT 1
           FROM public.profiles p
          WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'client'::text) AND (p.active = true))))))));


--
-- Name: service_accounts Clients can read their linked service account; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clients can read their linked service account" ON public.service_accounts FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.account_access a
  WHERE ((a.account_id = service_accounts.id) AND (a.user_id = ( SELECT auth.uid() AS uid)) AND (a.active = true)))));


--
-- Name: account_access Clients can read their own active account link; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clients can read their own active account link" ON public.account_access FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) AND (active = true) AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = ( SELECT auth.uid() AS uid)) AND (p.role = 'client'::text) AND (p.active = true))))));


--
-- Name: service_concerns Clients can submit concerns for their account; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clients can submit concerns for their account" ON public.service_concerns FOR INSERT TO authenticated WITH CHECK (((submitted_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM (public.account_access a
     JOIN public.profiles p ON ((p.user_id = a.user_id)))
  WHERE ((a.account_id = service_concerns.account_id) AND (a.user_id = ( SELECT auth.uid() AS uid)) AND (a.active = true) AND (p.role = 'client'::text) AND (p.active = true))))));


--
-- Name: profiles Users can read their own active profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can read their own active profile" ON public.profiles FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) AND (active = true)));


--
-- Name: account_access; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.account_access ENABLE ROW LEVEL SECURITY;

--
-- Name: announcements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

--
-- Name: bills; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bills ENABLE ROW LEVEL SECURITY;

--
-- Name: offline_payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.offline_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: repair_tickets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.repair_tickets ENABLE ROW LEVEL SECURITY;

--
-- Name: service_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.service_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: service_concerns; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.service_concerns ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION rls_auto_enable(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.rls_auto_enable() TO anon;
GRANT ALL ON FUNCTION public.rls_auto_enable() TO authenticated;
GRANT ALL ON FUNCTION public.rls_auto_enable() TO service_role;


--
-- Name: TABLE account_access; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.account_access TO service_role;
GRANT SELECT ON TABLE public.account_access TO authenticated;


--
-- Name: TABLE announcements; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.announcements TO service_role;
GRANT SELECT ON TABLE public.announcements TO authenticated;


--
-- Name: COLUMN announcements.title; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(title),UPDATE(title) ON TABLE public.announcements TO authenticated;


--
-- Name: COLUMN announcements.message; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(message),UPDATE(message) ON TABLE public.announcements TO authenticated;


--
-- Name: COLUMN announcements.published; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(published),UPDATE(published) ON TABLE public.announcements TO authenticated;


--
-- Name: COLUMN announcements.created_by; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(created_by) ON TABLE public.announcements TO authenticated;


--
-- Name: COLUMN announcements.updated_by; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(updated_by),UPDATE(updated_by) ON TABLE public.announcements TO authenticated;


--
-- Name: COLUMN announcements.updated_at; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(updated_at) ON TABLE public.announcements TO authenticated;


--
-- Name: TABLE bills; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.bills TO service_role;
GRANT SELECT,INSERT ON TABLE public.bills TO authenticated;


--
-- Name: TABLE offline_payments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.offline_payments TO service_role;
GRANT SELECT,INSERT ON TABLE public.offline_payments TO authenticated;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.profiles TO service_role;
GRANT SELECT ON TABLE public.profiles TO authenticated;


--
-- Name: TABLE repair_tickets; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.repair_tickets TO service_role;
GRANT SELECT ON TABLE public.repair_tickets TO authenticated;


--
-- Name: COLUMN repair_tickets.concern_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(concern_id) ON TABLE public.repair_tickets TO authenticated;


--
-- Name: COLUMN repair_tickets.assigned_to; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(assigned_to),UPDATE(assigned_to) ON TABLE public.repair_tickets TO authenticated;


--
-- Name: COLUMN repair_tickets.status; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(status),UPDATE(status) ON TABLE public.repair_tickets TO authenticated;


--
-- Name: COLUMN repair_tickets.latest_update; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(latest_update),UPDATE(latest_update) ON TABLE public.repair_tickets TO authenticated;


--
-- Name: COLUMN repair_tickets.created_by; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(created_by) ON TABLE public.repair_tickets TO authenticated;


--
-- Name: COLUMN repair_tickets.updated_by; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(updated_by),UPDATE(updated_by) ON TABLE public.repair_tickets TO authenticated;


--
-- Name: COLUMN repair_tickets.updated_at; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(updated_at) ON TABLE public.repair_tickets TO authenticated;


--
-- Name: TABLE service_accounts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.service_accounts TO service_role;
GRANT SELECT,INSERT,UPDATE ON TABLE public.service_accounts TO authenticated;


--
-- Name: TABLE service_concerns; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.service_concerns TO service_role;
GRANT SELECT ON TABLE public.service_concerns TO authenticated;


--
-- Name: COLUMN service_concerns.account_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(account_id) ON TABLE public.service_concerns TO authenticated;


--
-- Name: COLUMN service_concerns.submitted_by; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(submitted_by) ON TABLE public.service_concerns TO authenticated;


--
-- Name: COLUMN service_concerns.category; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(category) ON TABLE public.service_concerns TO authenticated;


--
-- Name: COLUMN service_concerns.subject; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(subject) ON TABLE public.service_concerns TO authenticated;


--
-- Name: COLUMN service_concerns.description; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(description) ON TABLE public.service_concerns TO authenticated;


--
-- Name: COLUMN service_concerns.status; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(status) ON TABLE public.service_concerns TO authenticated;


--
-- Name: COLUMN service_concerns.admin_response; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(admin_response) ON TABLE public.service_concerns TO authenticated;


--
-- Name: COLUMN service_concerns.reviewed_by; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(reviewed_by) ON TABLE public.service_concerns TO authenticated;


--
-- Name: COLUMN service_concerns.reviewed_at; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(reviewed_at) ON TABLE public.service_concerns TO authenticated;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--


