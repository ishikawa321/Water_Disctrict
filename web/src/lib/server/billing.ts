import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HttpError } from "./http";

export async function billingCall(
  supabase: SupabaseClient,
  name: string,
  input?: Record<string, unknown>,
) {
  const result = await supabase.rpc(name, input);
  if (result.error?.code === "PGRST202")
    throw new HttpError(
      503,
      input && "p_release_date" in input
        ? "Run database/billing-release-dates.sql in the Supabase SQL Editor to enable your chosen release dates. Your draft is retained."
        : "Complete the Supabase billing setup to enable automatic numbers, payment confirmation and daily interest. Your draft is retained.",
      "billing_setup_required",
    );
  return result;
}

// Preserve reads during migration; never fall back to unsafe legacy writes.
export async function refreshBilling(supabase: SupabaseClient) {
  const result = await supabase.rpc("wd_billing_refresh");
  if (result.error?.code === "PGRST202") return;
  if (result.error)
    throw new HttpError(
      503,
      "The current billing balance could not be confirmed. Refresh to retry.",
    );
}
