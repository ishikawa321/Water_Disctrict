import { requirePage } from "@/lib/server/auth";
import { OfficeDashboard } from "@/components/office-dashboard";
export default async function Page() {
  const { profile } = await requirePage(["admin", "staff"]);
  return <OfficeDashboard profile={profile} />;
}
