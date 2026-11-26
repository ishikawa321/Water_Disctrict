import { beforeEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { PDFDocument } from "pdf-lib";
const state = vi.hoisted(() => ({
  role: "admin",
  bills: [] as Record<string, unknown>[],
  payments: [] as Record<string, unknown>[],
  calls: [] as string[],
  failure: false,
}));
vi.mock("@/lib/server/auth", () => ({
  authenticate: async (roles: string[]) => {
    const { HttpError } = await import("@/lib/server/http");
    if (!roles.includes(state.role))
      throw new HttpError(state.role === "anonymous" ? 401 : 403, "Forbidden");
    return {
      profile: { displayName: "QA Office user", role: state.role },
      supabase: client(),
    };
  },
}));
function client() {
  return {
    rpc: async (name: string) => {
      state.calls.push(name);
      return { data: null, error: state.failure ? { code: "503" } : null };
    },
    from(table: string) {
      let values = table === "bills" ? state.bills : state.payments;
      const chain = {
        select() {
          return chain;
        },
        in(field: string, ids: string[]) {
          state.calls.push(`${table}:in:${ids.length}`);
          values = values.filter((r) => ids.includes(String(r[field])));
          return chain;
        },
        order() {
          return chain;
        },
        range(start: number, end: number) {
          state.calls.push(`${table}:range:${start}`);
          values = values.slice(start, end + 1);
          return chain;
        },
        then(resolve: (value: unknown) => void) {
          return Promise.resolve({ data: values, error: null }).then(resolve);
        },
      };
      return chain;
    },
  } as unknown as SupabaseClient;
}
import { GET, POST } from "@/app/api/office/billing-pdf/route";
import { billingExportRecords } from "@/lib/server/billing-export";
const id = "30000000-0000-4000-8000-000000000001";
const otherId = "30000000-0000-4000-8000-000000000002";
function post(body: unknown, origin = "https://district.test") {
  return POST(
    new Request("https://district.test/api/office/billing-pdf", {
      method: "POST",
      headers: { origin, "content-type": "application/json" },
      body: JSON.stringify(body),
    }),
  );
}
function get(billId = id) {
  return GET(
    new Request(
      `https://district.test/api/office/billing-pdf?billId=${billId}`,
    ),
  );
}
beforeEach(() => {
  state.role = "admin";
  state.calls = [];
  state.failure = false;
  state.bills = [
    {
      id,
      bill_number: "QA-001",
      due_date: "2026-11-24",
      amount_due: "515.00",
      base_amount_due: "500.00",
      interest_amount: "15.00",
      interest_days: 3,
      service_accounts: {
        account_number: "QA-001",
        holder_name: "José Muñoz",
        service_address: "Maramag, Bukidnon",
      },
    },
  ];
  state.payments = [{ bill_id: id, amount_paid: "100.00" }];
});
describe("authenticated office billing PDFs", () => {
  it.each(["admin", "staff"])(
    "lets active %s download an actual uncached bill PDF",
    async (role) => {
      state.role = role;
      const response = await get();
      expect(response.status).toBe(200);
      expect(response.headers.get("content-type")).toBe("application/pdf");
      expect(response.headers.get("content-disposition")).toBe(
        'attachment; filename="waterdistrict-bill-QA-001.pdf"',
      );
      expect(response.headers.get("cache-control")).toContain("no-store");
      expect(response.headers.get("vary")).toBe("Cookie");
      const pdf = await PDFDocument.load(await response.arrayBuffer());
      expect(pdf.getTitle()).toBe("Billing record QA-001");
      expect(pdf.getPages()).toHaveLength(1);
      expect(state.calls[0]).toBe("wd_billing_refresh");
    },
  );
  it.each([
    ["anonymous", 401],
    ["client", 403],
  ])("rejects %s before querying any financial data", async (role, status) => {
    state.role = String(role);
    expect((await get()).status).toBe(status);
    expect((await post({ billIds: [id] })).status).toBe(status);
    expect(state.calls).toEqual([]);
  });
  it("validates the selected IDs, origin and request size before reading bills", async () => {
    for (const billIds of [
      [],
      ["invalid"],
      [id, "invalid"],
      Array(1001).fill(id),
    ])
      expect((await post({ billIds })).status).toBe(422);
    expect((await get("invalid")).status).toBe(422);
    expect((await post({ billIds: [id] }, "https://other.test")).status).toBe(
      403,
    );
    expect(
      (await post({ billIds: [id], padding: "x".repeat(65536) })).status,
    ).toBe(413);
    expect(state.calls).toEqual([]);
  });
  it("fails the entire report if any selected bill was deleted or is inaccessible", async () => {
    const response = await post({ billIds: [id, otherId] });
    expect(response.status).toBe(404);
    expect(response.headers.get("content-type")).toContain("application/json");
    expect(state.calls.some((c) => c.startsWith("offline_payments"))).toBe(
      false,
    );
  });
  it("returns an error rather than a PDF if the current balance cannot be confirmed", async () => {
    state.failure = true;
    expect((await get()).status).toBe(503);
  });
  it("sums all payment pages exactly and uses saved amounts rather than browser supplied totals", async () => {
    state.payments = Array.from({ length: 501 }, () => ({
      bill_id: id,
      amount_paid: "0.10",
    }));
    const records = await billingExportRecords(client(), [id]);
    expect(records[0]).toMatchObject({
      baseAmount: "500.00",
      interestAmount: "15.00",
      interestDays: 3,
      total: "515.00",
      paid: "50.10",
      remaining: "464.90",
      holderName: "José Muñoz",
    });
    expect(state.calls).toContain("offline_payments:range:500");
  });
  it("accepts 1,000 selected IDs without body-size truncation and paginates the report", async () => {
    const original = state.bills[0];
    state.bills = Array.from({ length: 1000 }, (_, i) => ({
      ...original,
      id: `30000000-0000-4000-8000-${String(i + 1).padStart(12, "0")}`,
      bill_number: `QA-${i + 1}`,
    }));
    const response = await post({
      billIds: state.bills.map((b) => b.id),
      amountDue: "0.01",
    });
    expect(response.status).toBe(200);
    const pdf = await PDFDocument.load(await response.arrayBuffer());
    expect(pdf.getPageCount()).toBeGreaterThan(1);
    expect(pdf.getPages().every((p) => p.getWidth() > p.getHeight())).toBe(
      true,
    );
    expect(state.calls.filter((c) => c === "bills:in:50")).toHaveLength(20);
  }, 20000);
  it("deduplicates selections so a bill cannot be counted twice", async () => {
    const response = await post({ billIds: [id, id] });
    expect(response.status).toBe(200);
    expect(state.calls).toContain("bills:in:1");
  });
});
