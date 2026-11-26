import { createSupabaseServer } from "@/lib/supabase/server";
import { authenticate } from "@/lib/server/auth";
import { homeFor } from "@/lib/policy";
import {
  errorResponse,
  HttpError,
  json,
  readBody,
  requireSameOrigin,
  textField,
  publicOrigin,
} from "@/lib/server/http";
export async function POST(
  request: Request,
  context: { params: Promise<{ action: string }> },
) {
  try {
    requireSameOrigin(request);
    const { action } = await context.params;
    const body = await readBody(request);
    const supabase = await createSupabaseServer();
    if (action === "staff-invitation" || action === "staff-signup") {
      const token = textField(body.token, "Invitation", 100);
      const invite = await supabase.rpc("wd_staff_invitation", {
        p_token: token,
      });
      if (invite.error || !invite.data)
        throw new HttpError(
          422,
          "This Staff invitation is invalid, expired or revoked. Contact your Admin.",
        );
      if (action === "staff-invitation") return json(invite.data);
      if (
        typeof body.password !== "string" ||
        body.password.length < 8 ||
        body.password.length > 128 ||
        body.password !== body.confirm
      )
        throw new HttpError(
          422,
          "Use matching passwords with 8 to 128 characters.",
        );
      const {
        data: { user: existing },
      } = await supabase.auth.getUser();
      if (existing)
        throw new HttpError(
          409,
          "Sign out of your current account before accepting a Staff invitation.",
        );
      const result = await supabase.auth.signUp({
        email: invite.data.email,
        password: body.password,
        options: {
          emailRedirectTo: `${publicOrigin(request)}/auth/callback`,
          data: {
            registration_source: "staff_invite_v1",
            staff_invite_token: token,
          },
        },
      });
      if (result.error)
        throw new HttpError(
          result.error.status === 429 ? 429 : 422,
          "Staff signup could not be confirmed. Check your invitation and email before retrying.",
        );
      if (result.data.session) await supabase.auth.signOut({ scope: "local" });
      return json({
        message:
          "Invitation accepted for signup. Confirm your email, then sign in with this password on web or mobile. Your Admin can disable access at any time.",
      });
    }
    if (action === "logout") {
      const { error } = await supabase.auth.signOut({ scope: "local" });
      if (error)
        throw new HttpError(
          503,
          "Sign-out could not be completed. Please retry.",
        );
      return json({ ok: true });
    }
    if (action === "signup") {
      const email = textField(body.email, "Email address", 254);
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
        throw new HttpError(422, "Enter a valid email address.");
      const fullName = textField(body.fullName, "Full name", 200);
      const serviceAddress = textField(
        body.serviceAddress,
        "Service address",
        500,
      );
      if (
        typeof body.password !== "string" ||
        body.password.length < 8 ||
        body.password.length > 128
      )
        throw new HttpError(422, "Use a password with 8 to 128 characters.");
      if (body.password !== body.confirm)
        throw new HttpError(422, "The passwords do not match.");
      const { data: ready, error: setupError } = await supabase.rpc(
        "client_registration_approval_available",
      );
      if (setupError || ready !== true)
        throw new HttpError(
          503,
          "Client registration is not available yet. Ask the administrator to finish the database setup.",
        );
      const { data, error } = await supabase.auth.signUp({
        email,
        password: body.password,
        options: {
          emailRedirectTo: `${publicOrigin(request)}/auth/callback`,
          data: {
            registration_source: "client_signup_v1",
            display_name: fullName,
            service_address: serviceAddress,
          },
        },
      });
      if (error)
        throw new HttpError(
          error.status === 429 ? 429 : 422,
          error.status === 429
            ? "Too many attempts. Wait before registering again."
            : "Registration could not be completed. Check your details and email before retrying.",
        );
      if (data.session) await supabase.auth.signOut({ scope: "local" });
      return json({
        message: data.session
          ? "Registration submitted. Wait for administrator approval before signing in. Your account number is assigned when approved."
          : "Check your email to confirm registration and wait for administrator approval. You can sign in after both are complete. Your account number is assigned when approved.",
      });
    }
    if (action === "login") {
      const email = textField(body.email, "Email address", 254);
      if (typeof body.password !== "string" || !body.password)
        throw new HttpError(422, "Enter your password.");
      const { error } = await supabase.auth.signInWithPassword({
        email,
        password: body.password,
      });
      if (error)
        throw new HttpError(
          error.status === 429 ? 429 : 401,
          error.status === 429
            ? "Too many attempts. Wait a moment before trying again."
            : "Sign-in failed. Check your email, password and verified account.",
        );
      try {
        const { profile } = await authenticate();
        return json({ redirect: homeFor(profile.role) });
      } catch (error) {
        await supabase.auth.signOut({ scope: "local" });
        throw error;
      }
    }
    if (action === "recovery") {
      const email = textField(body.email, "Email address", 254);
      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${publicOrigin(request)}/auth/callback?next=/reset-password`,
      });
      if (error)
        throw new HttpError(
          error.status === 429 ? 429 : 503,
          "The recovery email could not be requested. Wait a moment and retry.",
        );
      return json({
        message:
          "If this email has an account, a recovery link has been requested. Open the newest email in this browser.",
      });
    }
    if (action === "password") {
      const {
        data: { user },
        error: sessionError,
      } = await supabase.auth.getUser();
      if (sessionError || !user)
        throw new HttpError(
          401,
          "This recovery session expired. Request a new recovery email.",
          "session_lost",
        );
      if (
        typeof body.password !== "string" ||
        body.password.length < 8 ||
        body.password.length > 128
      )
        throw new HttpError(422, "Use a password with 8 to 128 characters.");
      const { error } = await supabase.auth.updateUser({
        password: body.password,
      });
      if (error)
        throw new HttpError(
          422,
          "The password could not be updated. Choose a different password or request a new recovery link.",
        );
      await supabase.auth.signOut({ scope: "local" });
      return json({
        message: "Password updated. Sign in with your new password.",
      });
    }
    throw new HttpError(404, "Unknown account action.");
  } catch (error) {
    return errorResponse(error);
  }
}
