import { notFound } from "next/navigation";
import { requirePage } from "@/lib/server/auth";
import { canVisit } from "@/lib/policy";
import { ConsumerSection } from "@/components/consumer";
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
  const { profile } = await requirePage(["client"]);
  const { section } = await params;
  if (!canVisit(profile.role, section)) notFound();
  return (
    <ConsumerSection
      section={section}
      profile={profile}
      {...await searchParams}
    />
  );
}
