import { redirect } from "next/navigation";
import { authenticate } from "@/lib/server/auth";
import { HttpError } from "@/lib/server/http";
import { homeFor } from "@/lib/policy";
export default async function AppEntry() {
  const { profile } = await authenticate().catch((error: unknown) => {
    if (error instanceof HttpError) {
      // Opening the app without signing in is a normal first visit.
      if (error.status === 401) redirect("/login");
      if (error.status === 403) redirect(`/login?reason=${error.code}`);
    }
    throw error;
  });
  redirect(homeFor(profile.role));
}
