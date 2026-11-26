"use client";
import { useEffect, useRef, useState, type FormEvent } from "react";
import Link from "next/link";
import { save, message } from "@/lib/client";
import { Card, Field, Feedback, Brand } from "./ui";
export function StaffAcceptance() {
  const token = useRef("");
  const [invitation, setInvitation] = useState<{
    email: string;
    displayName: string;
  } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let active = true;
    async function load() {
      try {
        token.current = decodeURIComponent(window.location.hash.slice(1));
        if (!token.current)
          throw new Error("Open your private Staff invitation link.");
        const result = await save<{ email: string; displayName: string }>(
          "/api/auth/staff-invitation",
          { token: token.current },
        );
        if (active) setInvitation(result);
      } catch (error) {
        if (active) setError(message(error));
      }
    }
    void Promise.resolve().then(load);
    return () => {
      active = false;
    };
  }, []);
  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (busy) return;
    const form = e.currentTarget;
    const data = new FormData(form);
    setBusy(true);
    setError(null);
    try {
      const result = await save<{ message: string }>("/api/auth/staff-signup", {
        token: token.current,
        password: data.get("password"),
        confirm: data.get("confirm"),
      });
      setSuccess(result.message);
      form.reset();
    } catch (e) {
      setError(message(e));
    } finally {
      setBusy(false);
    }
  }
  return (
    <main
      className="page stack"
      style={{ maxWidth: 560, margin: "auto", padding: 24 }}
    >
      <Brand />
      <Card title="Accept Staff invitation">
        <Feedback error={error} success={success} />
        {invitation && !success && (
          <>
            <p>
              Welcome, {invitation.displayName}. This invitation is for{" "}
              {invitation.email}. Set your password, then confirm your email
              before signing in on web or mobile.
            </p>
            <form className="form" onSubmit={submit}>
              <fieldset disabled={busy}>
                <Field label="New Staff password">
                  <input
                    type="password"
                    name="password"
                    autoComplete="new-password"
                    minLength={8}
                    maxLength={128}
                    required
                  />
                </Field>
                <Field label="Confirm Staff password">
                  <input
                    type="password"
                    name="confirm"
                    autoComplete="new-password"
                    minLength={8}
                    maxLength={128}
                    required
                  />
                </Field>
                <button className="primary">
                  {busy ? "Submitting…" : "Accept invitation"}
                </button>
              </fieldset>
            </form>
          </>
        )}
        <Link href="/login">Go to sign in</Link>
      </Card>
    </main>
  );
}
