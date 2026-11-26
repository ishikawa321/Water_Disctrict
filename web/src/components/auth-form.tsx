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
  const [register, setRegister] = useState(false);
  const [busy, setBusy] = useState(false);
  const lock = useRef(false);
  const [visible, setVisible] = useState(false);
  const [error, setError] = useState<string | null>(
    reason === "registration_pending"
      ? "Your registration is awaiting administrator approval."
      : reason === "access_lost"
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
    const formElement = event.currentTarget;
    const form = new FormData(formElement);
    const password = String(form.get("password") ?? "");
    if ((reset || register) && password !== form.get("confirm")) {
      setError("The passwords do not match.");
      return;
    }
    setBusy(true);
    lock.current = true;
    setError(null);
    setSuccess(null);
    try {
      const result = await save<{ redirect?: string; message?: string }>(
        `/api/auth/${reset ? "password" : register ? "signup" : recover ? "recovery" : "login"}`,
        {
          email: form.get("email"),
          password,
          confirm: form.get("confirm"),
          fullName: form.get("fullName"),
          serviceAddress: form.get("serviceAddress"),
        },
      );
      if (result.redirect) window.location.replace(result.redirect);
      else {
        setSuccess(result.message ?? "Saved.");
        if (register) formElement.reset();
      }
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
              : register
                ? "Create your account"
                : recover
                  ? "Forgot your password?"
                  : "Welcome back"}
          </h1>
          <p>
            {reset
              ? "Choose a secure password for your existing account."
              : register
                ? "Submit your details for administrator approval. Confirm your email and wait for approval before signing in."
                : recover
                  ? "We’ll send a recovery link to your account email."
                  : "Sign in to access your district services."}
          </p>
          <Feedback error={error} success={success} />
          <form className="form" onSubmit={submit} aria-busy={busy}>
            {register && (
              <>
                <Field label="Full name">
                  <input
                    name="fullName"
                    autoComplete="name"
                    maxLength={200}
                    required
                    disabled={busy}
                  />
                </Field>
                <Field label="Service address">
                  <textarea
                    name="serviceAddress"
                    autoComplete="street-address"
                    maxLength={500}
                    required
                    disabled={busy}
                  />
                </Field>
              </>
            )}
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
                      autoComplete={
                        reset || register ? "new-password" : "current-password"
                      }
                      minLength={reset || register ? 8 : undefined}
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
                {(reset || register) && (
                  <Field
                    label={
                      register ? "Confirm password" : "Confirm new password"
                    }
                  >
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
            {!reset && !recover && !register && (
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
              disabled={busy || ((reset || register) && !!success)}
            >
              {busy
                ? "Please wait…"
                : reset
                  ? "Update password"
                  : register
                    ? "Create account"
                    : recover
                      ? "Send recovery email"
                      : "Sign in"}
              <ArrowRight size={17} />
            </button>
            {!reset && !recover && !register && (
              <button
                type="button"
                className="text-button"
                disabled={busy}
                onClick={() => {
                  setRegister(true);
                  setError(null);
                  setSuccess(null);
                }}
              >
                Create account
              </button>
            )}
            {(recover || register) && (
              <button
                type="button"
                className="text-button row"
                disabled={busy}
                onClick={() => {
                  setRecover(false);
                  setRegister(false);
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
            Administrator approval creates your service account and assigns the
            next account number. Existing clients, Admin and Staff can sign in
            with their current accounts.
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
