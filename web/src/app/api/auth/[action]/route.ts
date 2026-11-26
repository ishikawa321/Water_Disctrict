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
    if (action === "logout") {
      const { error } = await supabase.auth.signOut({ scope: "local" });
      if (error)
        throw new HttpError(
          503,
          "Sign-out could not be completed. Please retry.",
        );
      return json({ ok: true });
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
