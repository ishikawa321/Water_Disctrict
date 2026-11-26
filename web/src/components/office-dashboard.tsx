"use client";
import Link from "next/link";
import {
  ArrowUpRight,
  MessageSquare,
  Wrench,
  Users,
  FileText,
  CreditCard,
  Megaphone,
  Contact,
} from "lucide-react";
import type { Profile } from "@/lib/types";
import { useResource } from "@/lib/hooks";
import { Card } from "./ui";
import { DashboardHeader } from "./dashboard-header";
import { DataState, Refresh } from "./data-ui";
export function OfficeDashboard({ profile }: { profile: Profile }) {
  const summary = useResource<{
    pendingConcerns: number;
    activeRepairs: number;
  }>(profile.role === "admin" ? "/api/office/office/summary" : null);
  const links = [
    {
      href: "concerns",
      title: "Service concerns",
      text: "Receive and review reports",
      Icon: MessageSquare,
    },
    {
      href: "repairs",
      title: profile.role === "staff" ? "Assigned repairs" : "Repair tickets",
      text:
        profile.role === "staff"
          ? "Update your assigned work"
          : "Dispatch and coordinate work",
      Icon: Wrench,
    },
    ...(profile.role === "admin"
      ? [
          {
            href: "accounts",
            title: "Service accounts",
            text: "Manage account records",
            Icon: Users,
          },
          {
            href: "bills",
            title: "Billing",
            text: "Enter district-computed bills",
            Icon: FileText,
          },
          {
            href: "payments",
            title: "Verified payments",
            text: "Record verified offline payments",
            Icon: CreditCard,
          },
          {
            href: "announcements",
            title: "Announcements",
            text: "Create and publish notices",
            Icon: Megaphone,
          },
          {
            href: "staff",
            title: "Staff directory",
            text: "View authorized personnel",
            Icon: Contact,
          },
        ]
      : []),
  ];
  return (
    <>
      <DashboardHeader
        title={`Welcome back, ${profile.displayName.split(" ")[0]}.`}
        subtitle={
          profile.role === "admin"
            ? "Receive concerns, manage district records and coordinate repairs."
            : "Review concerns and update repairs assigned to you."
        }
      />
      {profile.role === "admin" && (
        <>
          <div className="page-header">
            <div>
              <h2 style={{ marginBottom: 0 }}>District overview</h2>
              <p>Exact counts from shared district records.</p>
            </div>
            <Refresh onClick={summary.reload} busy={summary.busy} />
          </div>
          <DataState {...summary} loaded={!!summary.data}>
            <div className="stats water-surface office-overview">
              <Card className="stat">
                <div className="stat-icon">
                  <MessageSquare size={21} />
                </div>
                <p>Pending concerns</p>
                <strong>{summary.data?.pendingConcerns ?? "—"}</strong>
                <p>Submitted and Under review</p>
                <Link className="text-button" href="/office/concerns">
                  Review concerns →
                </Link>
              </Card>
              <Card className="stat">
                <div className="stat-icon">
                  <Wrench size={21} />
                </div>
                <p>Active repairs</p>
                <strong>{summary.data?.activeRepairs ?? "—"}</strong>
                <p>Open, Assigned and In progress</p>
                <Link className="text-button" href="/office/repairs">
                  View repairs →
                </Link>
              </Card>
            </div>
          </DataState>
        </>
      )}
      <Card title="Your daily workspace">
        <div className="quick-grid">
          {links.map(({ href, title, text, Icon }) => (
            <Link href={`/office/${href}`} className="quick-link" key={href}>
              <Icon size={23} strokeWidth={1.6} />
              <span>
                {title}
                <small>{text}</small>
              </span>
              <ArrowUpRight size={16} />
            </Link>
          ))}
        </div>
      </Card>
    </>
  );
}
