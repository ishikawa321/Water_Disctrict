import { requirePage } from "@/lib/server/auth";
import { Shell } from "@/components/shell";
export default async function Layout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { profile } = await requirePage(["admin", "staff"]);
  return <Shell profile={profile}>{children}</Shell>;
}
