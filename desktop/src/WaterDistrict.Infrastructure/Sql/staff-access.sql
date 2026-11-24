-- Add the application Staff role without changing any existing user's role.
-- Existing consumer ownership policies and column-specific write grants remain intact.
ALTER TABLE public.profiles DROP CONSTRAINT profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK(role IN ('client','admin','staff'));
CREATE FUNCTION public.wd_is_active_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.profiles WHERE user_id=auth.uid() AND active AND role='admin')
$fn$;
REVOKE ALL ON FUNCTION public.wd_is_active_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.wd_is_active_admin() TO authenticated;
CREATE POLICY wd_admin_office_directory ON public.profiles FOR SELECT TO authenticated
 USING(active AND role IN ('admin','staff') AND public.wd_is_active_admin());
