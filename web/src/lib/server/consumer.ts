import "server-only";
import type { SupabaseClient, PostgrestError } from "@supabase/supabase-js";
import type { Account } from "@/lib/types";
import { HttpError } from "./http";
import Decimal from "decimal.js";
export async function paymentTotals(
  supabase: SupabaseClient,
  billIds: string[],
) {
  const totals = new Map<string, Decimal>();
  for (let batch = 0; batch < billIds.length; batch += 50) {
    for (let offset = 0; ; offset += 500) {
      const { data, error } = await supabase
        .from("offline_payments")
        .select("id,bill_id,amount_paid")
        .in("bill_id", billIds.slice(batch, batch + 50))
        .order("id")
        .range(offset, offset + 499);
      checkData(error);
      for (const payment of data ?? [])
        totals.set(
          payment.bill_id,
          (totals.get(payment.bill_id) ?? new Decimal(0)).plus(
            String(payment.amount_paid),
          ),
        );
      if ((data?.length ?? 0) < 500) break;
    }
  }
  return totals;
}
export async function consumerSummary(
  supabase: SupabaseClient,
  accountId: string,
) {
  let outstanding = new Decimal(0),
    billCount = 0;
  let nextDueDate: string | null = null;
  for (let offset = 0; ; offset += 500) {
    const { data, error } = await supabase
      .from("bills")
      .select("id,amount_due,due_date")
      .eq("account_id", accountId)
      .order("id")
      .range(offset, offset + 499);
    checkData(error);
    const totals = await paymentTotals(
      supabase,
      (data ?? []).map((bill) => bill.id),
    );
    for (const bill of data ?? []) {
      billCount++;
      const remaining = Decimal.max(
        0,
        new Decimal(String(bill.amount_due)).minus(totals.get(bill.id) ?? 0),
      );
      outstanding = outstanding.plus(remaining);
      if (remaining.gt(0) && (!nextDueDate || bill.due_date < nextDueDate))
        nextDueDate = bill.due_date;
    }
    if ((data?.length ?? 0) < 500) break;
  }
  return { outstanding: outstanding.toFixed(2), billCount, nextDueDate };
}
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
