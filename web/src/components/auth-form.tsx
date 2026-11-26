"use client";
import { useRef, useState, type FormEvent } from "react";
import Link from "next/link";
import { ArrowLeft, ArrowRight, Droplets, Eye, EyeOff } from "lucide-react";
import { Brand, Feedback, Field } from "./ui";
import { message, save } from "@/lib/client";
export function AuthForm({
  reset = false,
  reason = "",
}: {
  reset?: boolean;
  reason?: string;
}) {
  const [recover, setRecover] = useState(false);
  const [busy, setBusy] = useState(false);
  const lock = useRef(false);
  const [visible, setVisible] = useState(false);
  const [error, setError] = useState<string | null>(
    reason === "access_lost"
      ? "Your app profile is disabled or unavailable. Contact authorized district personnel."
      : reason === "session_lost"
        ? "Your session has ended. Sign in again."
        : reason === "recovery_expired"
          ? "This recovery link is expired or was already used. Request a new email."
          : null,
  );
  const [success, setSuccess] = useState<string | null>(null);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (lock.current) return;
    const form = new FormData(event.currentTarget);
    const password = String(form.get("password") ?? "");
    if (reset && password !== form.get("confirm")) {
      setError("The passwords do not match.");
      return;
    }
    setBusy(true);
    lock.current = true;
    setError(null);
    setSuccess(null);
    try {
      const result = await save<{ redirect?: string; message?: string }>(
        `/api/auth/${reset ? "password" : recover ? "recovery" : "login"}`,
        { email: form.get("email"), password },
      );
      if (result.redirect) window.location.replace(result.redirect);
      else setSuccess(result.message ?? "Saved.");
    } catch (error) {
      setError(message(error));
    } finally {
      setBusy(false);
      lock.current = false;
    }
  }
  return (
    <div className="auth-layout">
      <aside className="auth-story">
        <Brand />
        <div>
          <div className="water-icon">
            <Droplets size={36} strokeWidth={1.5} />
          </div>
          <div className="eyebrow" style={{ color: "var(--blue)" }}>
            Your district. Connected.
          </div>
          <h1>
            Better service.
            <br />
            Every day.
          </h1>
          <p>
            Your water services and the people keeping them flowing, in one
            connected place.
          </p>
        </div>
        <div>
          <strong>Maramag, Bukidnon</strong>
          <p style={{ fontSize: 12, marginTop: 7 }}>
            Consumer services · Office workspace
          </p>
        </div>
      </aside>
      <main className="auth-form-area">
        <div className="auth-form">
          <div className="mobile-brand">
            <Brand />
          </div>
          <div className="eyebrow">Water District Connect</div>
          <h1>
            {reset
              ? "Set a new password"
              : recover
                ? "Forgot your password?"
                : "Welcome back"}
          </h1>
          <p>
            {reset
              ? "Choose a secure password for your existing account."
              : recover
                ? "We’ll send a recovery link to your account email."
                : "Sign in to access your district services."}
          </p>
          <Feedback error={error} success={success} />
          <form className="form" onSubmit={submit} aria-busy={busy}>
            {!reset && (
              <Field label="Email address">
                <input
                  name="email"
                  type="email"
                  autoComplete="email"
                  placeholder="you@example.com"
                  maxLength={254}
                  required
                  disabled={busy}
                />
              </Field>
            )}
            {(!recover || reset) && (
              <>
                <Field label={reset ? "New password" : "Password"}>
                  <div style={{ position: "relative" }}>
                    <input
                      name="password"
                      type={visible ? "text" : "password"}
                      autoComplete={reset ? "new-password" : "current-password"}
                      minLength={reset ? 8 : undefined}
                      maxLength={128}
                      required
                      disabled={busy}
                      style={{ paddingRight: 48 }}
                    />
                    <button
                      className="text-button"
                      type="button"
                      aria-label={visible ? "Hide password" : "Show password"}
                      onClick={() => setVisible(!visible)}
                      style={{ position: "absolute", right: 13, top: 2 }}
                    >
                      {visible ? <EyeOff size={18} /> : <Eye size={18} />}
                    </button>
                  </div>
                </Field>
                {reset && (
                  <Field label="Confirm new password">
                    <input
                      name="confirm"
                      type="password"
                      autoComplete="new-password"
                      minLength={8}
                      maxLength={128}
                      required
                      disabled={busy}
                    />
                  </Field>
                )}
              </>
            )}
            {!reset && !recover && (
              <button
                type="button"
                className="text-button"
                style={{ alignSelf: "flex-end", marginTop: -9 }}
                onClick={() => {
                  setRecover(true);
                  setError(null);
                  setSuccess(null);
                }}
              >
                Forgot password?
              </button>
            )}
            <button
              className="primary"
              type="submit"
              disabled={busy || (reset && !!success)}
            >
              {busy
                ? "Please wait…"
                : reset
                  ? "Update password"
                  : recover
                    ? "Send recovery email"
                    : "Sign in"}
              <ArrowRight size={17} />
            </button>
            {recover && (
              <button
                type="button"
                className="text-button row"
                onClick={() => {
                  setRecover(false);
                  setError(null);
                  setSuccess(null);
                }}
              >
                <ArrowLeft size={16} /> Back to sign in
              </button>
            )}
            {reset && (
              <Link className="text-button" href="/login">
                Back to sign in
              </Link>
            )}
          </form>
          <p className="auth-note">
            Use your existing Water District account.
            <br />
            For account access or linking, contact authorized district
            personnel.
          </p>
          <a
            className="text-button"
            href={process.env.NEXT_PUBLIC_LANDING_URL || "/"}
          >
            ← Back to the website
          </a>
        </div>
      </main>
    </div>
  );
}
