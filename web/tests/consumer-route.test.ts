import { beforeEach, describe, expect, it, vi } from "vitest";
const state = vi.hoisted(() => ({
  tables: new Map<string, { data: unknown; error: unknown }>(),
  calls: [] as { table: string; method: string; args: unknown[] }[],
  role: "client",
}));
vi.mock("@/lib/server/auth", () => ({
  authenticate: async (roles: string[]) => {
    if (!roles.includes(state.role)) {
      const { HttpError } = await import("@/lib/server/http");
      throw new HttpError(403, "Forbidden");
    }
    return {
      profile: {
        userId: "11111111-1111-4111-8111-111111111111",
        role: state.role,
      },
      supabase: {
        from: (table: string) => {
          const chain: Record<string, unknown> = {};
          for (const method of [
            "select",
            "eq",
            "limit",
            "range",
            "order",
            "ilike",
            "insert",
            "in",
          ])
            chain[method] = (...args: unknown[]) => {
              state.calls.push({ table, method, args });
              return chain;
            };
          const result = () =>
            state.tables.get(table) ?? { data: null, error: null };
          chain.maybeSingle = async () => result();
          chain.single = async () => result();
          chain.then = (resolve: (value: unknown) => void) =>
            Promise.resolve(result()).then(resolve);
          return chain;
        },
      },
    };
  },
}));
import { GET, POST } from "@/app/api/consumer/[resource]/route";
const accountId = "22222222-2222-4222-8222-222222222222";
const billId = "33333333-3333-4333-8333-333333333333";
const requestId = "44444444-4444-4444-8444-444444444444";
const context = (resource: string) => ({
  params: Promise.resolve({ resource }),
});
describe("consumer request ownership", () => {
  beforeEach(() => {
    state.role = "client";
    state.calls = [];
    state.tables.clear();
    state.tables.set("account_access", {
      data: [{ account_id: accountId }],
      error: null,
    });
    state.tables.set("service_accounts", {
      data: {
        id: accountId,
        account_number: "TEST-1",
        holder_name: "Consumer",
        service_address: "Test street",
        active: true,
      },
      error: null,
    });
  });
  it("forces published-only notice reads and no office access", async () => {
    state.tables.set("announcements", { data: [], error: null });
    expect(
      (
        await GET(
          new Request("https://district.test/api/consumer/announcements"),
          context("announcements"),
        )
      ).status,
    ).toBe(200);
    expect(state.calls).toContainEqual({
      table: "announcements",
      method: "eq",
      args: ["published", true],
    });
    state.role = "staff";
    expect(
      (
        await GET(
          new Request("https://district.test/api/consumer/bills"),
          context("bills"),
        )
      ).status,
    ).toBe(403);
  });
  it("filters bills by the verified link rather than a browser account parameter", async () => {
    state.tables.set("bills", { data: [], error: null });
    await GET(
      new Request(
        "https://district.test/api/consumer/bills?accountId=someone-else",
      ),
      context("bills"),
    );
    expect(state.calls).toContainEqual({
      table: "bills",
      method: "eq",
      args: ["account_id", accountId],
    });
  });
  it("checks bill ownership before reading any payments", async () => {
    state.tables.set("bills", { data: null, error: null });
    expect(
      (
        await GET(
          new Request(
            `https://district.test/api/consumer/payments?billId=${billId}`,
          ),
          context("payments"),
        )
      ).status,
    ).toBe(404);
    expect(state.calls).toContainEqual({
      table: "bills",
      method: "eq",
      args: ["account_id", accountId],
    });
    expect(state.calls.some((c) => c.table === "offline_payments")).toBe(false);
  });
  it("derives submission account and actor on the server and never accepts a browser status", async () => {
    const body = {
      requestId,
      accountId: "other-account",
      submitted_by: "admin",
      status: "Resolved",
      category: "Other",
      subject: "Test report",
      description: "Test description",
    };
    // The chained test fixture returns null on the idempotency read and a saved ID on insert.
    const saved = { id: requestId };
    let reads = 0;
    state.tables.set("service_concerns", {
      get data() {
        return reads++ ? saved : null;
      },
      error: null,
    });
    const response = await POST(
      new Request("https://district.test/api/consumer/concerns", {
        method: "POST",
        headers: {
          origin: "https://district.test",
          "content-type": "application/json",
        },
        body: JSON.stringify(body),
      }),
      context("concerns"),
    );
    expect(response.status).toBe(201);
    const write = state.calls.find((c) => c.method === "insert")?.args[0];
    expect(write).toEqual({
      id: requestId,
      account_id: accountId,
      submitted_by: "11111111-1111-4111-8111-111111111111",
      category: "Other",
      subject: "Test report",
      description: "Test description",
    });
  });
  it("denies unlinked or inactive account submissions without a write", async () => {
    state.tables.set("account_access", { data: [], error: null });
    const response = await POST(
      new Request("https://district.test/api/consumer/concerns", {
        method: "POST",
        headers: {
          origin: "https://district.test",
          "content-type": "application/json",
        },
        body: "{}",
      }),
      context("concerns"),
    );
    expect(response.status).toBe(403);
    expect(state.calls.some((c) => c.method === "insert")).toBe(false);
  });
});
