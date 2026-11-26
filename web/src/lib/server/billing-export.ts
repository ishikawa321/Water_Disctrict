import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import Decimal from "decimal.js";
import { balance } from "@/lib/format";
import { relatedOne } from "@/lib/policy";
import { refreshBilling } from "./billing";
import { checkData, paymentTotals } from "./consumer";
import { HttpError, uuid } from "./http";

export type BillingExport = {
  id: string;
  billNumber: string;
  accountNumber: string;
  holderName: string;
  serviceAddress: string;
  dueDate: string;
  baseAmount: string;
  interestAmount: string;
  interestDays: number;
  total: string;
  paid: string;
  remaining: string;
};
export function billingExportIds(value: unknown): string[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 1000)
    throw new HttpError(
      422,
      "Choose between 1 and 1,000 loaded billing records to export.",
    );
  return [...new Set(value.map(uuid))];
}
function savedText(value: unknown): string {
  if (typeof value !== "string" || !value.trim())
    throw new HttpError(
      503,
      "A saved billing record is incomplete. Refresh before exporting.",
    );
  return value;
}
function savedAmount(value: unknown): string {
  try {
    const amount = new Decimal(String(value));
    if (!amount.isFinite() || amount.isNegative()) throw new Error();
    return amount.toFixed(2);
  } catch {
    throw new HttpError(503, "A saved billing amount could not be confirmed.");
  }
}
export async function billingExportRecords(
  supabase: SupabaseClient,
  ids: string[],
): Promise<BillingExport[]> {
  await refreshBilling(supabase);
  const records = new Map<string, Record<string, unknown>>();
  for (let offset = 0; offset < ids.length; offset += 50) {
    const result = await supabase
      .from("bills")
      .select("*,service_accounts(account_number,holder_name,service_address)")
      .in("id", ids.slice(offset, offset + 50));
    checkData(result.error);
    for (const r of result.data ?? []) records.set(r.id, r);
  }
  if (ids.some((id) => !records.has(id)))
    throw new HttpError(
      404,
      "One or more selected bills are unavailable. Refresh the billing list before exporting.",
    );
  const totals = await paymentTotals(supabase, ids);
  return ids.map((id) => {
    const r = records.get(id)!;
    const account = relatedOne<Record<string, unknown>>(r.service_accounts);
    const total = savedAmount(r.amount_due);
    const days = Number(r.interest_days ?? 0);
    if (!Number.isSafeInteger(days) || days < 0)
      throw new HttpError(
        503,
        "Saved interest details could not be confirmed.",
      );
    return {
      id,
      billNumber: savedText(r.bill_number),
      accountNumber:
        typeof account?.account_number === "string"
          ? account.account_number
          : "Unavailable",
      holderName:
        typeof account?.holder_name === "string"
          ? account.holder_name
          : "Unavailable",
      serviceAddress:
        typeof account?.service_address === "string"
          ? account.service_address
          : "Unavailable",
      dueDate: savedText(r.due_date),
      baseAmount: savedAmount(r.base_amount_due ?? r.amount_due),
      interestAmount: savedAmount(r.interest_amount ?? 0),
      interestDays: days,
      total,
      ...balance(total, [(totals.get(id) ?? new Decimal(0)).toString()]),
    };
  });
}
