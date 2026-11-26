import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";
const state = vi.hoisted(() => ({
  role: "admin",
  calls: [] as { table: string; method: string; args: unknown[] }[],
  tables: new Map<string, { data: unknown; error: unknown; count?: number }>(),
  rpcResult: { data: null as unknown, error: null as unknown },
}));
vi.mock("@/lib/server/auth", () => ({
  authenticate: async (roles: string[]) => {
    if (!roles.includes(state.role)) {
      const { HttpError } = await import("@/lib/server/http");
      throw new HttpError(403, "Forbidden");
    }
    return {
      profile: {
        userId: "10000000-0000-4000-8000-000000000001",
        displayName: "Office user",
        role: state.role,
      },
      supabase: {
        from: (table: string) => {
          const chain: Record<string, unknown> = {};
          for (const method of [
            "select",
            "eq",
            "in",
            "order",
            "limit",
            "range",
            "or",
            "ilike",
            "insert",
            "update",
          ])
            chain[method] = (...args: unknown[]) => {
              state.calls.push({ table, method, args });
              return chain;
            };
          const result = () =>
            state.tables.get(table) ?? { data: [], error: null };
          chain.then = (resolve: (value: unknown) => void) =>
            Promise.resolve(result()).then(resolve);
          chain.single = chain.maybeSingle = async () => {
            const value = result();
            return {
              ...value,
              data: Array.isArray(value.data)
                ? (value.data[0] ?? null)
                : value.data,
            };
          };
          return chain;
        },
        rpc: async (name: string, input: unknown) => {
          state.calls.push({ table: name, method: "rpc", args: [input] });
          return state.rpcResult;
        },
      },
    };
  },
}));
import { GET, POST, PUT } from "@/app/api/office/[...path]/route";
const accountId = "20000000-0000-4000-8000-000000000001",
  id = "40000000-0000-4000-8000-000000000001",
  ticketId = "50000000-0000-4000-8000-000000000001";
const rawConcern = {
  id,
  xmin: "515",
  account_id: accountId,
  category: "Repair request",
  subject: "Saved concern",
  description: "Actual saved description",
  status: "Under review",
  admin_response: null,
  created_at: "2026-11-26T08:00:00Z",
  reviewed_at: null,
  repair_dispatched_at: null,
  latitude: 7.76,
  longitude: 125,
  location_note: "Near meter",
  service_accounts: { account_number: "TEST-001", holder_name: "Test holder" },
  repair_tickets: [],
};
const rawTicket = {
  id: ticketId,
  xmin: "516",
  concern_id: id,
  status: "Open",
  assigned_to: null,
  assigned_to_user_id: null,
  latest_update: "Created for repair",
  updated_at: "2026-11-26T08:00:00Z",
  service_concerns: {
    subject: "Saved concern",
    account_id: accountId,
    service_accounts: { account_number: "TEST-001" },
  },
};
function call(
  method: "GET" | "POST" | "PUT",
  path: string,
  body: unknown = {},
) {
  const request = new Request("https://district.test/api/office/" + path, {
    method,
    ...(method === "GET"
      ? {}
      : {
          headers: {
            origin: "https://district.test",
            "content-type": "application/json",
          },
          body: JSON.stringify(body),
        }),
  });
  return { GET, POST, PUT }[method](request, {
    params: Promise.resolve({ path: path.split("/") }),
  });
}
describe("Supabase office routes without a desktop server", () => {
  beforeEach(() => {
    state.role = "admin";
    state.calls = [];
    state.tables.clear();
    state.rpcResult = { data: null, error: null };
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockRejectedValue(new Error("No external C# server is available")),
    );
    vi.stubEnv("WATERDISTRICT_API_URL", "https://obsolete-api.example.test");
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });
  it("loads saved repairs from caller-scoped Supabase and ignores the obsolete API setting", async () => {
    state.tables.set("repair_tickets", { data: [rawTicket], error: null });
    const response = await call("GET", "workflow/tickets");
    expect(response.status).toBe(200);
    expect((await response.json())[0]).toMatchObject({
      id: ticketId,
      version: 516,
      subject: "Saved concern",
      accountNumber: "TEST-001",
    });
    expect(fetch).not.toHaveBeenCalled();
  });
  it("keeps exact overview counts instead of using bounded list lengths", async () => {
    state.tables.set("service_concerns", {
      data: null,
      error: null,
      count: 700,
    });
    state.tables.set("repair_tickets", {
      data: null,
      error: null,
      count: 1500,
    });
    const result = await call("GET", "office/summary");
    expect(await result.json()).toEqual({
      pendingConcerns: 700,
      activeRepairs: 1500,
    });
    expect(
      state.calls
        .filter((c) => c.method === "select")
        .every((c) => (c.args[1] as { head: boolean }).head),
    ).toBe(true);
  });
  it("restricts Staff ticket reads to their own assignment and denies Admin modules", async () => {
    state.role = "staff";
    state.tables.set("repair_tickets", { data: [], error: null });
    expect((await call("GET", "workflow/tickets")).status).toBe(200);
    expect(state.calls).toContainEqual({
      table: "repair_tickets",
      method: "eq",
      args: ["assigned_to_user_id", "10000000-0000-4000-8000-000000000001"],
    });
    for (const path of [
      "office/summary",
      "office/accounts",
      "office/bills",
      "admin/staff",
    ])
      expect((await call("GET", path)).status).toBe(403);
    expect((await call("POST", "workflow/tickets", {})).status).toBe(403);
  });
  it("stamps account creation with the validated actor rather than the supplied actor", async () => {
    state.tables.set("service_accounts", {
      data: {
        id: accountId,
        account_number: "TEST-001",
        holder_name: "Holder",
        service_address: "Street",
        active: true,
      },
      error: null,
    });
    const response = await call("POST", "office/accounts", {
      accountNumber: "TEST-001",
      holderName: "Holder",
      serviceAddress: "Street",
      updated_by: "attacker",
      active: false,
    });
    expect(response.status).toBe(200);
    expect(
      state.calls.find((c) => c.method === "insert")?.args[0],
    ).toMatchObject({
      updated_by: "10000000-0000-4000-8000-000000000001",
      active: true,
    });
  });
  it("fails a missing workflow RPC without a direct mutation fallback or external API call", async () => {
    state.rpcResult = { data: null, error: { code: "PGRST202" } };
    const response = await call("POST", "workflow/concerns", {
      requestId: id,
      accountId,
      category: "Repair request",
      subject: "A concern",
      description: "A description",
      latitude: 7.76,
      longitude: 125,
      locationNote: "Near meter",
    });
    expect(response.status).toBe(503);
    expect((await response.json()).code).toBe("workflow_setup_required");
    expect(
      state.calls.some((c) => c.method === "insert" || c.method === "update"),
    ).toBe(false);
    expect(fetch).not.toHaveBeenCalled();
  });
  it("sends the expected xmin to the locked review transaction, then reads the confirmed record", async () => {
    state.rpcResult = { data: { id }, error: null };
    state.tables.set("service_concerns", { data: rawConcern, error: null });
    const response = await call("PUT", `workflow/concerns/${id}/review`, {
      version: 515,
      status: "Under review",
      response: "Reviewed",
      reviewed_by: "attacker",
    });
    expect(response.status).toBe(200);
    expect(state.calls.find((c) => c.method === "rpc")?.args[0]).toEqual({
      p_action: "review",
      p_id: id,
      p_version: 515,
      p_payload: { status: "Under review", response: "Reviewed" },
    });
  });
  it("retains a conflict as HTTP 409 and never overwrites directly", async () => {
    state.rpcResult = { data: null, error: { code: "40001" } };
    const response = await call("PUT", `workflow/tickets/${ticketId}`, {
      version: 515,
      status: "Assigned",
      assignedToUserId: "10000000-0000-4000-8000-000000000002",
      note: "Assign staff",
    });
    expect(response.status).toBe(409);
    expect((await response.json()).code).toBe("conflict");
    expect(state.calls.some((c) => c.method === "update")).toBe(false);
  });
  it("shows existing history through RLS even before the name function is installed", async () => {
    state.tables.set("repair_tickets", { data: rawTicket, error: null });
    state.rpcResult = { data: null, error: { code: "PGRST202" } };
    state.tables.set("ticket_status_history", {
      data: [
        {
          id: 1,
          status: "Open",
          note: "Saved event",
          changed_by: "10000000-0000-4000-8000-000000000001",
          assigned_to: null,
          changed_at: "2026-11-26T08:00:00Z",
        },
      ],
      error: null,
    });
    const response = await call("GET", `workflow/tickets/${ticketId}`);
    expect(response.status).toBe(200);
    expect((await response.json()).history[0]).toMatchObject({
      note: "Saved event",
      changedBy: "Office user",
    });
  });
  it("rejects unverified offline payments and invalid expected versions before database writes", async () => {
    expect(
      (
        await call("POST", "office/payments", {
          billId: accountId,
          paymentDate: "2026-11-25",
          amountPaid: "50.00",
          verified: false,
        })
      ).status,
    ).toBe(422);
    expect(
      (
        await call("PUT", `workflow/tickets/${ticketId}`, {
          version: 0,
          status: "Assigned",
          note: "No version",
        })
      ).status,
    ).toBe(422);
    expect(state.calls).toEqual([]);
  });
  it("denies consumer access to office routes", async () => {
    state.role = "client";
    expect((await call("GET", "workflow/tickets")).status).toBe(403);
    expect(state.calls).toEqual([]);
  });
});
