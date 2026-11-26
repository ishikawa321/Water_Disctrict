import "server-only";
import type { SupabaseClient, PostgrestError } from "@supabase/supabase-js";
import type { Account } from "@/lib/types";
import { HttpError } from "./http";
export function checkData(error: PostgrestError | null) {
  if (!error) return;
  const status =
    error.code === "42501"
      ? 403
      : error.code === "23505"
        ? 409
        : ["23514", "23503", "22P02"].includes(error.code)
          ? 422
          : 503;
  throw new HttpError(
    status,
    status === 403
      ? "Access to this record was denied. Check your active account link."
      : status === 409
        ? "This record already exists. Refresh before retrying."
        : status === 422
          ? "The database rejected these values. Check the form and retry."
          : "The data service could not confirm the result. Refresh before retrying.",
    error.code,
  );
}
export async function linkedAccount(
  supabase: SupabaseClient,
  userId: string,
): Promise<Account | null> {
  const { data: links, error } = await supabase
    .from("account_access")
    .select("account_id")
    .eq("user_id", userId)
    .eq("active", true)
    .limit(2);
  checkData(error);
  if (!links?.length) return null;
  if (links.length !== 1)
    throw new HttpError(
      409,
      "More than one active account link is configured. Contact authorized district personnel.",
    );
  const { data, error: accountError } = await supabase
    .from("service_accounts")
    .select("id,account_number,holder_name,service_address,active")
    .eq("id", links[0].account_id)
    .maybeSingle();
  checkData(accountError);
  return data
    ? {
        id: data.id,
        accountNumber: data.account_number,
        holderName: data.holder_name,
        serviceAddress: data.service_address,
        active: data.active,
      }
    : null;
}
export function pageNumber(value: string | null) {
  const page = Number(value ?? 0);
  if (!Number.isInteger(page) || page < 0 || page > 100000)
    throw new HttpError(422, "Select a valid page.");
  return page;
}
