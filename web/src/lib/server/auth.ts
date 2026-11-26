import "server-only";
import { redirect } from "next/navigation";
import { createSupabaseServer } from "@/lib/supabase/server";
import { isRole, homeFor } from "@/lib/policy";
import type { Profile, Role } from "@/lib/types";
import { HttpError } from "./http";
export async function authenticate(roles?: Role[]) {
  const supabase = await createSupabaseServer();
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();
  if (error || !user) {
    if (error && (!error.status || error.status >= 500))
      throw new HttpError(
        503,
        "Authentication is temporarily unavailable. Please retry.",
        "dependency",
      );
    throw new HttpError(
      401,
      "Your session has ended. Sign in again.",
      "session_lost",
    );
  }
  const { data, error: profileError } = await supabase
    .from("profiles")
    .select("user_id,display_name,role,active")
    .eq("user_id", user.id)
    .maybeSingle();
  if (profileError)
    throw new HttpError(
      503,
      "Your account access could not be checked. Please retry.",
      "dependency",
    );
  if (!data?.active || data.user_id !== user.id || !isRole(data.role)) {
    const { data: registration, error: registrationError } = await supabase
      .from("client_registrations")
      .select("status")
      .eq("user_id", user.id)
      .maybeSingle();
    if (registrationError)
      throw new HttpError(
        503,
        "Your registration status could not be checked. Please retry.",
        "dependency",
      );
    if (registration?.status === "Pending")
      throw new HttpError(
        403,
        "Your registration is awaiting administrator approval.",
        "registration_pending",
      );
    throw new HttpError(
      403,
      "No active app profile is available. Contact authorized district personnel.",
      "access_lost",
    );
  }
  const profile: Profile = {
    userId: user.id,
    displayName: data.display_name,
    role: data.role,
    email: user.email ?? "",
  };
  if (roles && !roles.includes(profile.role))
    throw new HttpError(
      403,
      "Your role does not permit this operation.",
      "forbidden",
    );
  return { supabase, profile, user };
}
export async function requirePage(roles?: Role[]) {
  try {
    return await authenticate(roles);
  } catch (error) {
    if (error instanceof HttpError && [401, 403].includes(error.status)) {
      if (error.code === "forbidden") {
        const { profile } = await authenticate();
        redirect(homeFor(profile.role));
      }
      redirect(`/login?reason=${error.code}`);
    }
    throw error;
  }
}
