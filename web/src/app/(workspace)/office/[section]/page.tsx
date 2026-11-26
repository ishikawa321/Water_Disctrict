import { notFound, redirect } from "next/navigation";
import { requirePage } from "@/lib/server/auth";
import { canVisit, moduleNames } from "@/lib/policy";
import {
  AccountsPage,
  BillsPage,
  PaymentsPage,
  AnnouncementEditor,
  StaffDirectory,
} from "@/components/office-management";
import { ConcernsPage, RepairsPage } from "@/components/workflows";
export default async function Page({
  params,
  searchParams,
}: {
  params: Promise<{ section: string }>;
  searchParams: Promise<{
    billId?: string;
    concernId?: string;
    ticketId?: string;
  }>;
}) {
  const { profile } = await requirePage(["admin", "staff"]);
  const { section } = await params;
  if (!moduleNames[section]) notFound();
  if (!canVisit(profile.role, section)) redirect("/office");
  const query = await searchParams;
  return section === "accounts" ? (
    <AccountsPage />
  ) : section === "bills" ? (
    <BillsPage />
  ) : section === "payments" ? (
    <PaymentsPage initialBillId={query.billId} />
  ) : section === "announcements" ? (
    <AnnouncementEditor />
  ) : section === "staff" ? (
    <StaffDirectory />
  ) : section === "concerns" ? (
    <ConcernsPage profile={profile} initialSelected={query.concernId} />
  ) : (
    <RepairsPage profile={profile} initialSelected={query.ticketId} />
  );
}
