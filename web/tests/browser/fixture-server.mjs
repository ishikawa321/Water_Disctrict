// Isolated loopback fixtures for browser QA. Never imported by application code.
import { createServer } from "node:http";
const ids = {
  admin: "10000000-0000-4000-8000-000000000001",
  staff: "10000000-0000-4000-8000-000000000002",
  client: "10000000-0000-4000-8000-000000000003",
  other: "10000000-0000-4000-8000-000000000004",
  account: "20000000-0000-4000-8000-000000000001",
  bill: "30000000-0000-4000-8000-000000000001",
  concern: "40000000-0000-4000-8000-000000000001",
  ticket: "50000000-0000-4000-8000-000000000001",
  notice: "60000000-0000-4000-8000-000000000001",
};
const now = "2026-11-26T08:00:00Z";
const account = {
  id: ids.account,
  accountNumber: "QA-001",
  holderName: "QA Consumer",
  serviceAddress: "Isolated test address",
  active: true,
};
const bill = {
  id: ids.bill,
  billNumber: "QA-BILL-001",
  accountNumber: account.accountNumber,
  periodStart: "2026-11-01",
  periodEnd: "2026-11-30",
  dueDate: "2026-12-15",
  amountDue: "450.00",
  paid: "100.00",
  remaining: "350.00",
};
const payment = {
  receiptReference: "QA-RECEIPT-001",
  billNumber: bill.billNumber,
  accountNumber: account.accountNumber,
  paymentDate: "2026-11-25",
  amountPaid: "100.00",
  verifiedAt: now,
};
let state;
function reset() {
  state = {
    revoked: [],
    unlinked: false,
    failNextWrite: false,
    accounts: [account],
    bills: [bill],
    payments: [payment],
    concerns: [
      {
        id: ids.concern,
        accountId: ids.account,
        accountNumber: account.accountNumber,
        holderName: account.holderName,
        category: "Water supply",
        subject: "QA low pressure",
        description: "Isolated test report.",
        status: "Submitted",
        response: null,
        createdAt: now,
        reviewedAt: null,
        ticketId: null,
        version: 1,
      },
    ],
    tickets: [],
    notices: [
      {
        id: ids.notice,
        title: "[Service interruption] QA maintenance",
        message: "A published test notice.",
        published: true,
        updatedAt: now,
      },
      {
        id: "60000000-0000-4000-8000-000000000002",
        title: "QA private draft",
        message: "A private test draft.",
        published: false,
        updatedAt: now,
      },
    ],
  };
}
reset();
function jwt(role) {
  const encode = (value) =>
    Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "HS256", typ: "JWT" })}.${encode({ sub: ids[role], role: "authenticated", aud: "authenticated", exp: Math.floor(Date.now() / 1000) + 3600, iat: Math.floor(Date.now() / 1000) })}.test-signature`;
}
function roleFor(request) {
  try {
    const token = request.headers.authorization?.split(" ")[1];
    const { sub } = JSON.parse(
      Buffer.from(token.split(".")[1], "base64url").toString(),
    );
    return Object.keys(ids).find((role) => ids[role] === sub);
  } catch {
    return undefined;
  }
}
function user(role) {
  return {
    id: ids[role],
    aud: "authenticated",
    role: "authenticated",
    email: `${role}@example.test`,
    email_confirmed_at: now,
    app_metadata: {},
    user_metadata: {},
    created_at: now,
  };
}
function session(role) {
  return {
    access_token: jwt(role),
    token_type: "bearer",
    expires_in: 3600,
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    refresh_token: `qa-refresh-${role}`,
    user: user(role),
  };
}
function respond(response, body, status = 200) {
  response.writeHead(status, {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  });
  response.end(JSON.stringify(body));
}
function fail(response, detail, status = 403) {
  respond(
    response,
    {
      detail,
      message: detail,
      code: status === 409 ? "conflict" : "forbidden",
    },
    status,
  );
}
function rows(request, response, values, url) {
  const id = url.searchParams.get("id")?.replace("eq.", "");
  if (id) values = values.filter((row) => row.id === id);
  const range = request.headers.range;
  const offset = Number(
    url.searchParams.get("offset") ?? range?.split("-")[0] ?? 0,
  );
  const limit = Number(
    url.searchParams.get("limit") ??
      (range ? Number(range.split("-")[1]) - offset + 1 : 1000),
  );
  values = values.slice(offset, offset + limit);
  respond(
    response,
    request.headers.accept?.includes("vnd.pgrst.object")
      ? (values[0] ?? null)
      : values,
  );
}
createServer(async (request, response) => {
  const url = new URL(request.url, "http://127.0.0.1:54339");
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  let body = {};
  try {
    body = JSON.parse(Buffer.concat(chunks).toString() || "{}");
  } catch {
    return fail(response, "Invalid JSON", 422);
  }
  if (url.pathname === "/__test/reset") {
    reset();
    return respond(response, { ids });
  }
  if (url.pathname === "/__test/scenario") {
    if (body.bumpConcern) state.concerns[0].version++;
    else Object.assign(state, body);
    return respond(response, { ok: true });
  }
  if (url.pathname === "/health") return respond(response, { ok: true });
  let role = roleFor(request);
  if (url.pathname === "/auth/v1/token") {
    role =
      body.email?.split("@")[0] ??
      body.refresh_token?.replace("qa-refresh-", "");
    if (
      !["admin", "staff", "client", "other"].includes(role) ||
      (body.password && body.password !== "test-password")
    )
      return respond(
        response,
        {
          error: "invalid_grant",
          error_description: "Invalid test credentials",
        },
        400,
      );
    return respond(response, session(role));
  }
  if (url.pathname === "/auth/v1/logout" || url.pathname === "/auth/v1/recover")
    return respond(response, {});
  if (url.pathname === "/auth/v1/user")
    return role
      ? respond(response, user(role))
      : fail(response, "Invalid token", 401);
  if (!role) return fail(response, "Authentication required", 401);
  const active = !state.revoked.includes(role);
  if (url.pathname.startsWith("/rest/v1/")) {
    const table = url.pathname.split("/").pop();
    if (table === "profiles")
      return rows(
        request,
        response,
        active
          ? [
              {
                user_id: ids[role],
                display_name: `QA ${role[0].toUpperCase() + role.slice(1)}`,
                role: role === "other" ? "client" : role,
                active: true,
              },
            ]
          : [],
        url,
      );
    if (!active) return fail(response, "Inactive profile");
    if (table === "account_access")
      return rows(
        request,
        response,
        state.unlinked || role === "other" ? [] : [{ account_id: ids.account }],
        url,
      );
    if (table === "service_accounts")
      return rows(
        request,
        response,
        [
          {
            id: ids.account,
            account_number: account.accountNumber,
            holder_name: account.holderName,
            service_address: account.serviceAddress,
            active: true,
          },
        ],
        url,
      );
    if (table === "announcements")
      return rows(
        request,
        response,
        state.notices
          .filter((n) => n.published)
          .map((n) => ({ ...n, updated_at: n.updatedAt })),
        url,
      );
    if (table === "bills")
      return rows(
        request,
        response,
        state.bills.map((b) => ({
          id: b.id,
          bill_number: b.billNumber,
          billing_period_start: b.periodStart,
          billing_period_end: b.periodEnd,
          due_date: b.dueDate,
          amount_due: b.amountDue,
          offline_payments: [{ amount_paid: b.paid }],
        })),
        url,
      );
    if (table === "offline_payments")
      return rows(
        request,
        response,
        state.payments.map((p, i) => ({
          id: `qa-${i}`,
          bill_id: ids.bill,
          receipt_reference: p.receiptReference,
          payment_date: p.paymentDate,
          amount_paid: p.amountPaid,
          verified_at: p.verifiedAt,
        })),
        url,
      );
    if (table === "service_concerns") {
      if (request.method === "POST") {
        if (state.failNextWrite) {
          state.failNextWrite = false;
          return fail(response, "Simulated test service failure", 503);
        }
        const c = {
          id: body.id,
          accountId: body.account_id,
          accountNumber: account.accountNumber,
          holderName: account.holderName,
          category: body.category,
          subject: body.subject,
          description: body.description,
          status: "Submitted",
          response: null,
          createdAt: now,
          reviewedAt: null,
          ticketId: null,
          version: 1,
          submittedBy: ids[role],
        };
        state.concerns.push(c);
        return rows(request, response, [{ id: c.id }], url);
      }
      return rows(
        request,
        response,
        state.concerns.map((c) => ({
          id: c.id,
          account_id: c.accountId,
          submitted_by: c.submittedBy ?? ids.client,
          category: c.category,
          subject: c.subject,
          description: c.description,
          status: c.status,
          admin_response: c.response,
          created_at: c.createdAt,
          reviewed_at: c.reviewedAt,
          repair_tickets: c.ticketId ? [{ id: c.ticketId }] : [],
        })),
        url,
      );
    }
    if (table === "repair_tickets")
      return rows(
        request,
        response,
        state.tickets.map((t) => ({
          ...t,
          concern_id: t.concernId,
          assigned_to: t.assignedTo,
          latest_update: t.latestUpdate,
          updated_at: t.updatedAt,
          service_concerns: { account_id: ids.account, subject: t.subject },
        })),
        url,
      );
    return rows(request, response, [], url);
  }
  if (!active || !["admin", "staff"].includes(role))
    return fail(response, "Office access required");
  const path = url.pathname.replace("/api/", "");
  if (path.startsWith("office/") && role !== "admin")
    return fail(response, "Admin required");
  if (state.failNextWrite && request.method !== "GET") {
    state.failNextWrite = false;
    return fail(response, "Simulated test save failure", 503);
  }
  if (path === "office/summary")
    return respond(response, {
      pendingConcerns: state.concerns.filter((c) =>
        ["Submitted", "Under review"].includes(c.status),
      ).length,
      activeRepairs: state.tickets.filter((t) => t.status !== "Resolved")
        .length,
    });
  if (path === "office/accounts") {
    if (request.method === "POST")
      state.accounts.push({ id: crypto.randomUUID(), ...body, active: true });
    return respond(
      response,
      request.method === "POST" ? state.accounts.at(-1) : state.accounts,
    );
  }
  if (path === "office/bills") {
    if (request.method === "POST")
      state.bills.push({
        id: crypto.randomUUID(),
        accountNumber: account.accountNumber,
        ...body,
        paid: "0.00",
        remaining: body.amountDue,
      });
    return respond(
      response,
      request.method === "POST" ? state.bills.at(-1) : state.bills,
    );
  }
  if (path === "office/payments") {
    if (request.method === "POST")
      state.payments.push({
        ...body,
        billNumber: bill.billNumber,
        accountNumber: account.accountNumber,
        verifiedAt: now,
      });
    return respond(
      response,
      request.method === "POST" ? state.payments.at(-1) : state.payments,
    );
  }
  if (path.startsWith("office/announcements")) {
    if (request.method === "GET") return respond(response, state.notices);
    const id = path.split("/")[2] ?? crypto.randomUUID();
    const saved = {
      id,
      ...body,
      title: `${body.isInterruption ? "[Service interruption] " : ""}${body.title}`,
      updatedAt: now,
    };
    state.notices = [...state.notices.filter((n) => n.id !== id), saved];
    return respond(response, saved);
  }
  if (path === "admin/staff" || path === "workflow/assignees")
    return role === "admin"
      ? respond(response, [
          { userId: ids.staff, displayName: "QA Staff", role: "staff" },
        ])
      : fail(response, "Admin required");
  if (path === "workflow/accounts") return respond(response, state.accounts);
  if (path === "workflow/concerns") return respond(response, state.concerns);
  if (path.startsWith("workflow/concerns/")) {
    const c = state.concerns.find((c) => c.id === path.split("/")[2]);
    if (!c) return fail(response, "Concern unavailable", 404);
    if (request.method === "PUT") {
      if (body.version !== c.version)
        return fail(
          response,
          "This record changed. Reload before saving.",
          409,
        );
      Object.assign(c, {
        status: body.status,
        response: body.response,
        reviewedAt: now,
        version: c.version + 1,
      });
    }
    return respond(response, c);
  }
  if (path === "workflow/tickets") {
    if (request.method === "POST") {
      if (role !== "admin") return fail(response, "Admin required");
      const c = state.concerns.find((c) => c.id === body.concernId);
      if (!c || c.ticketId || c.status !== "Under review")
        return fail(
          response,
          "Review before dispatch; only one ticket is allowed",
          409,
        );
      const ticket = {
        id: crypto.randomUUID(),
        concernId: c.id,
        accountNumber: c.accountNumber,
        subject: c.subject,
        status: "Open",
        assignedTo: null,
        assignedToUserId: null,
        latestUpdate: body.note,
        updatedAt: now,
        version: 1,
        history: [
          {
            id: 1,
            status: "Open",
            note: body.note,
            changedBy: "QA Admin",
            assignedTo: null,
            changedAt: now,
          },
        ],
      };
      c.ticketId = ticket.id;
      state.tickets.push(ticket);
      return respond(response, { ticket, history: ticket.history });
    }
    return respond(
      response,
      state.tickets.filter(
        (t) => role === "admin" || t.assignedToUserId === ids[role],
      ),
    );
  }
  if (path.startsWith("workflow/tickets/")) {
    const t = state.tickets.find((t) => t.id === path.split("/")[2]);
    if (!t) return fail(response, "Ticket unavailable", 404);
    if (role === "staff" && t.assignedToUserId !== ids.staff)
      return fail(response, "Not your assigned ticket", 404);
    if (request.method === "PUT") {
      if (body.version !== t.version)
        return fail(response, "Ticket changed. Reload before saving.", 409);
      Object.assign(t, {
        ...body,
        version: t.version + 1,
        assignedTo: body.assignedToUserId ? "QA Staff" : null,
        latestUpdate: body.note,
      });
      t.history.push({
        id: t.history.length + 1,
        status: t.status,
        note: body.note,
        changedBy: `QA ${role}`,
        assignedTo: t.assignedTo,
        changedAt: now,
      });
      if (t.status === "Resolved")
        state.concerns.find((c) => c.id === t.concernId).status = "Resolved";
    }
    return respond(response, { ticket: t, history: t.history });
  }
  fail(response, "Unsupported fixture endpoint", 404);
}).listen(54339, "127.0.0.1", () =>
  process.stdout.write("Isolated browser fixtures ready on loopback:54339\n"),
);
