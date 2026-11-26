"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import {
  LayoutDashboard,
  Users,
  FileText,
  CreditCard,
  Megaphone,
  MessageSquare,
  Wrench,
  Contact,
  CircleHelp,
  UserRound,
  RefreshCw,
  LogOut,
  ChevronRight,
  Menu,
  X,
} from "lucide-react";
import type { Profile } from "@/lib/types";
import { canVisit, homeFor, moduleNames } from "@/lib/policy";
import { api, ClientError, message, save } from "@/lib/client";
import { DraftProvider } from "@/lib/hooks";
import { Brand, Feedback } from "./ui";
const icons = {
  accounts: Users,
  bills: FileText,
  payments: CreditCard,
  announcements: Megaphone,
  concerns: MessageSquare,
  repairs: Wrench,
  staff: Contact,
  profile: UserRound,
  help: CircleHelp,
};
export function Shell({
  profile,
  children,
}: {
  profile: Profile;
  children: ReactNode;
}) {
  const path = usePathname();
  const base = homeFor(profile.role);
  const section = path.split("/")[2] ?? "";
  const [open, setOpen] = useState(false);
  const [lost, setLost] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [drafts] = useState(() => new Map<string, unknown>());
  useEffect(() => {
    let stopped = false;
    let linkId: string | null | undefined;
    function loseAccount() {
      if (stopped) return;
      drafts.clear();
      setLost(true);
      window.location.replace("/portal/profile");
    }
    async function loseAccess() {
      if (stopped) return;
      setLost(true);
      drafts.clear();
      try {
        await save("/api/auth/logout", {});
      } catch {
        /* Protected server operations already deny access. */
      }
      window.location.replace("/login?reason=access_lost");
    }
    async function check() {
      if (document.visibilityState === "hidden") return;
      try {
        const next = await api<Profile & { accountLinkId: string | null }>(
          "/api/session",
        );
        if (stopped) return;
        if (next.userId !== profile.userId || next.role !== profile.role) {
          drafts.clear();
          setLost(true);
          window.location.replace(homeFor(next.role));
          return;
        }
        if (
          profile.role === "client" &&
          linkId !== undefined &&
          linkId !== next.accountLinkId
        ) {
          loseAccount();
          return;
        }
        linkId = next.accountLinkId;
        setError(null);
      } catch (error) {
        if (
          error instanceof ClientError &&
          (error.code === "session_lost" || error.code === "access_lost")
        )
          void loseAccess();
        else if (!stopped)
          setError(
            "Access could not be refreshed. Protected operations will check your access again.",
          );
      }
    }
    const onLost = () => {
      void loseAccess();
    };
    const onFocus = () => {
      void check();
    };
    const interval = setInterval(onFocus, 60000);
    window.addEventListener("waterdistrict:access-lost", onLost);
    window.addEventListener("waterdistrict:account-lost", loseAccount);
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", onFocus);
    void check();
    return () => {
      stopped = true;
      clearInterval(interval);
      window.removeEventListener("waterdistrict:access-lost", onLost);
      window.removeEventListener("waterdistrict:account-lost", loseAccount);
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onFocus);
    };
  }, [profile.userId, profile.role, drafts]);
  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open]);
  async function signOut() {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      await save("/api/auth/logout", {});
      drafts.clear();
      setLost(true);
      window.location.replace("/login");
    } catch (error) {
      setError(message(error));
      setBusy(false);
    }
  }
  if (lost)
    return (
      <main className="blank-state">
        <p role="status">Clearing your workspace…</p>
      </main>
    );
  const sections =
    profile.role === "client"
      ? [
          "bills",
          "payments",
          "concerns",
          "repairs",
          "announcements",
          "profile",
          "help",
        ]
      : [
          "concerns",
          "repairs",
          "accounts",
          "bills",
          "payments",
          "announcements",
          "staff",
        ];
  return (
    <DraftProvider drafts={drafts}>
      <div className="shell">
        <a href="#main" className="skip">
          Skip to content
        </a>
        <button
          className={`overlay ${open ? "show" : ""}`}
          tabIndex={open ? 0 : -1}
          aria-label="Close navigation"
          onClick={() => setOpen(false)}
        />
        <aside className={`sidebar ${open ? "open" : ""}`} id="workspace-nav">
          <Brand />
          <div className="nav-label">
            {profile.role === "client" ? "MY SERVICES" : "WORKSPACE"}
          </div>
          <nav className="navigation" aria-label="Workspace">
            <Link
              href={base}
              className={!section ? "active" : ""}
              aria-current={!section ? "page" : undefined}
              onClick={() => setOpen(false)}
            >
              <LayoutDashboard size={18} strokeWidth={1.7} />
              Dashboard
            </Link>
            {sections
              .filter((s) => canVisit(profile.role, s))
              .map((s) => {
                const Icon = icons[s as keyof typeof icons];
                return (
                  <Link
                    key={s}
                    href={`${base}/${s}`}
                    className={section === s ? "active" : ""}
                    aria-current={section === s ? "page" : undefined}
                    onClick={() => setOpen(false)}
                  >
                    <Icon size={18} strokeWidth={1.7} />
                    {profile.role === "client" && s === "bills"
                      ? "My bills"
                      : profile.role === "staff" && s === "repairs"
                        ? "Assigned repairs"
                        : moduleNames[s]}
                  </Link>
                );
              })}
          </nav>
          <div className="sidebar-bottom">
            <button
              className="text-button row"
              onClick={() => {
                void api<Profile>("/api/session")
                  .then(() => setError(null))
                  .catch((e) => setError(message(e)));
              }}
            >
              <RefreshCw size={17} />
              Refresh access
            </button>
            <br />
            <button
              className="text-button row"
              onClick={signOut}
              disabled={busy}
            >
              <LogOut size={17} />
              {busy ? "Signing out…" : "Sign out"}
            </button>
            <div className="identity">
              <span className="avatar">
                {profile.displayName.slice(0, 1).toUpperCase()}
              </span>
              <div>
                <div className="name" title={profile.displayName}>
                  {profile.displayName}
                </div>
                <small>
                  {profile.role === "client" ? "Consumer" : profile.role}
                </small>
              </div>
            </div>
          </div>
        </aside>
        <div className="workspace">
          <header className="topbar">
            <div className="row">
              <button
                className="mobile-toggle"
                aria-expanded={open}
                aria-controls="workspace-nav"
                aria-label={open ? "Close navigation" : "Open navigation"}
                onClick={() => setOpen(!open)}
              >
                {open ? <X size={23} /> : <Menu size={23} />}
              </button>
              <div className="breadcrumb">
                <span className="district-crumb">
                  {profile.role === "client"
                    ? "My services"
                    : "Office workspace"}
                </span>
                <ChevronRight className="district-crumb" size={14} />
                <strong>{moduleNames[section] ?? "Dashboard"}</strong>
              </div>
            </div>
            <div className="topbar-role">
              {profile.role === "client"
                ? "Consumer portal"
                : `${profile.role} workspace`}
            </div>
          </header>
          <main id="main" className="content">
            <Feedback error={error} />
            {children}
            <p className="footer-note">
              Maramag Water District · Updates reflect saved district records.
              Refresh to see the latest information.
            </p>
          </main>
        </div>
      </div>
    </DraftProvider>
  );
}
