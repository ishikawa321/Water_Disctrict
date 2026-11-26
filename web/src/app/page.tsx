import { redirect } from "next/navigation";
import { requirePage } from "@/lib/server/auth";
import { homeFor } from "@/lib/policy";
export default async function Home() {
  const { profile } = await requirePage();
  redirect(homeFor(profile.role));
}
