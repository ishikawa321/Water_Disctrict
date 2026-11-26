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
    for (const path of ["office/summary", "office/accounts", "admin/staff"])
      expect((await call("GET", path)).status).toBe(403);
    expect((await call("POST", "workflow/tickets", {})).status).toBe(403);
  });
  it("denies manual account creation", async () => {
    expect(
      (await call("POST", "office/accounts", { accountNumber: "TEST-001" }))
        .status,
    ).toBe(403);
    expect(state.calls.some((c) => c.method === "insert")).toBe(false);
  });
  it("approves registrations through the caller's Supabase RPC and returns the assigned number", async () => {
    state.rpcResult = { data: [{ account_number: "MWD-001250" }], error: null };
    const response = await call("POST", `office/registrations/${id}/approve`, {
      role: "admin",
      accountNumber: "ATTACKER",
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ accountNumber: "MWD-001250" });
    expect(state.calls).toContainEqual({
      table: "approve_client_registration",
      method: "rpc",
      args: [{ registration_user_id: id }],
    });
    expect(
      state.calls.some((c) => c.method === "insert" || c.method === "update"),
    ).toBe(false);
    state.role = "staff";
    expect(
      (await call("POST", `office/registrations/${id}/approve`)).status,
    ).toBe(403);
    expect((await call("GET", "office/registrations")).status).toBe(403);
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
  it("identifies missing registration setup without recommending repair migrations or creating accounts directly", async () => {
    state.rpcResult = { data: null, error: { code: "PGRST202" } };
    const approval = await call("POST", `office/registrations/${id}/approve`);
    expect(approval.status).toBe(503);
    expect((await approval.json()).code).toBe("registration_setup_required");
    state.tables.set("client_registrations", {
      data: null,
      error: { code: "PGRST205" },
    });
    const list = await call("GET", "office/registrations");
    expect(list.status).toBe(503);
    expect((await list.json()).code).toBe("registration_setup_required");
    expect(
      state.calls.some((c) => c.method === "insert" || c.method === "update"),
    ).toBe(false);
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
  it("creates bills with a server-generated number and no supplied billing period", async () => {
    state.rpcResult = { data: { id: ticketId }, error: null };
    state.tables.set("bills", {
      data: {
        id: ticketId,
        bill_number: "MWD-202611-1000000000",
        billing_period_start: "2026-11-01",
        billing_period_end: "2026-11-30",
        due_date: "2026-12-01",
        amount_due: "200.00",
        base_amount_due: "200.00",
        interest_amount: 0,
        interest_days: 0,
        service_accounts: { account_number: "TEST-001" },
      },
      error: null,
    });
    const response = await call("POST", "office/bills", {
      requestId: id,
      accountId,
      amountDue: "200.00",
      dueDate: "2026-12-01",
      billNumber: "forged",
      createdBy: "forged",
    });
    expect(response.status).toBe(200);
    expect((await response.json()).billNumber).toBe("MWD-202611-1000000000");
    expect(state.calls).toContainEqual({
      table: "wd_billing_create_bill",
      method: "rpc",
      args: [
        {
          p_request_id: id,
          p_account_id: accountId,
          p_amount: "200.00",
          p_due_date: "2026-12-01",
        },
      ],
    });
    expect(state.calls.some((c) => c.method === "insert")).toBe(false);
  });
  it("confirms a payment atomically and returns the generated reference", async () => {
    state.rpcResult = { data: { id: ticketId }, error: null };
    state.tables.set("offline_payments", {
      data: {
        id: ticketId,
        receipt_reference: "1000000001",
        payment_date: "2026-11-25",
        amount_paid: "50.00",
        verified_at: "2026-11-27T00:00:00Z",
        bills: {
          bill_number: "BILL-1",
          service_accounts: { account_number: "TEST-001" },
        },
      },
      error: null,
    });
    const response = await call("POST", "office/payments", {
      requestId: id,
      billId: ticketId,
      amountPaid: "50.00",
      paymentDate: "2026-11-25",
      verified: true,
      receiptReference: "forged",
      verifiedBy: "forged",
    });
    expect(response.status).toBe(200);
    expect((await response.json()).receiptReference).toMatch(/^\d{10}$/);
    expect(state.calls).toContainEqual({
      table: "wd_billing_confirm_payment",
      method: "rpc",
      args: [
        {
          p_request_id: id,
          p_bill_id: ticketId,
          p_amount: "50.00",
          p_payment_date: "2026-11-25",
        },
      ],
    });
    expect(state.calls.some((c) => c.method === "insert")).toBe(false);
  });
  it("retains a billing setup error instead of attempting a legacy payment insert", async () => {
    state.rpcResult = { data: null, error: { code: "PGRST202" } };
    const response = await call("POST", "office/payments", {
      requestId: id,
      billId: ticketId,
      amountPaid: "50.00",
      paymentDate: "2026-11-25",
      verified: true,
    });
    expect(response.status).toBe(503);
    expect((await response.json()).code).toBe("billing_setup_required");
    expect(state.calls.some((c) => c.method === "insert")).toBe(false);
    state.role = "staff";
    expect((await call("POST", "office/billing-plans", {})).status).toBe(403);
  });
});
