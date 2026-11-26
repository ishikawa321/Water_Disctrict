import { authenticate } from "@/lib/server/auth";
import { errorResponse, json } from "@/lib/server/http";
import { linkedAccount } from "@/lib/server/consumer";
export async function GET() {
  try {
    const { profile, supabase } = await authenticate();
    const account =
      profile.role === "client"
        ? await linkedAccount(supabase, profile.userId)
        : null;
    return json({ ...profile, accountLinkId: account?.id ?? null });
  } catch (error) {
    return errorResponse(error);
  }
}
