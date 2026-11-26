import { describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { consumerSummary } from "@/lib/server/consumer";
import { relatedOne } from "@/lib/policy";
describe("consumer overview", () => {
  it("includes every bill beyond the first data page and sums centavos without truncating or carrying an overpayment", async () => {
    const bills = Array.from({ length: 501 }, (_, i) => ({
      id: `bill-${i}`,
      account_id: "linked",
      amount_due: "0.30",
      due_date: i === 0 ? "2026-11-26" : i === 1 ? "2026-11-27" : "2026-12-15",
    }));
    const payments = bills.map((bill, i) => ({
      id: `payment-${i}`,
      bill_id: bill.id,
      amount_paid: i === 0 ? "0.40" : "0.10",
    }));
    const supabase = {
      from(table: string) {
        let rows: Record<string, unknown>[] =
          table === "bills" ? bills : payments;
        return {
          select() {
            return this;
          },
          order() {
            return this;
          },
          eq(field: string, value: string) {
            rows = rows.filter((row) => row[field] === value);
            return this;
          },
          in(field: string, values: string[]) {
            rows = rows.filter((row) => values.includes(String(row[field])));
            return this;
          },
          async range(start: number, end: number) {
            return { data: rows.slice(start, end + 1), error: null };
          },
        };
      },
    } as unknown as SupabaseClient;
    expect(await consumerSummary(supabase, "linked")).toEqual({
      outstanding: "100.00",
      billCount: 501,
      nextDueDate: "2026-11-27",
    });
    expect(await consumerSummary(supabase, "another-account")).toEqual({
      outstanding: "0.00",
      billCount: 0,
      nextDueDate: null,
    });
  });
  it("reads either one-to-one or one-to-many related ticket shapes", () => {
    expect(relatedOne({ id: "one" })).toEqual({ id: "one" });
    expect(relatedOne([{ id: "one" }])).toEqual({ id: "one" });
    expect(relatedOne([])).toBeNull();
    expect(relatedOne(null)).toBeNull();
  });
});
