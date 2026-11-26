import { requirePage } from "@/lib/server/auth";
import { Shell } from "@/components/shell";
export default async function Layout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { profile } = await requirePage(["client"]);
  return <Shell profile={profile}>{children}</Shell>;
}
