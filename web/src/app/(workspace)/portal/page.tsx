import { requirePage } from "@/lib/server/auth";
import { ConsumerDashboard } from "@/components/consumer";
export default async function Page() {
  const { profile } = await requirePage(["client"]);
  return <ConsumerDashboard profile={profile} />;
}
