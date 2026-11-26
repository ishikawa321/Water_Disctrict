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
    registrations: [],
    staffInvitations: [],
    unlinked: false,
    failNextWrite: false,
    workflowAvailable: true,
    billingAvailable: true,
    billingPlans: [],
    legacyApiRequests: 0,
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
        latitude: 7.7633,
        longitude: 125.0058,
        locationNote: "Beside the test service connection",
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
  for (const [field, filter] of url.searchParams) {
    if (["select", "order", "offset", "limit", "or"].includes(field)) continue;
    const fieldValue = (row) =>
      field.split(".").reduce((value, key) => value?.[key], row);
    if (filter.startsWith("eq."))
      values = values.filter(
        (row) => String(fieldValue(row)) === filter.slice(3),
      );
    if (filter.startsWith("in.(")) {
      const allowed = filter.slice(4, -1).split(",");
      values = values.filter((row) =>
        allowed.includes(String(fieldValue(row))),
      );
    }
    if (filter.startsWith("ilike.")) {
      const search = filter.slice(6).replaceAll("%", "").toLowerCase();
      values = values.filter((row) =>
        String(fieldValue(row)).toLowerCase().includes(search),
      );
    }
  }
  const total = values.length;
  if (request.method === "HEAD") {
    response.writeHead(200, {
      "content-range": total ? `0-${total - 1}/${total}` : "*/0",
      "cache-control": "no-store",
    });
    return response.end();
  }
  const offset = Number(url.searchParams.get("offset") ?? 0),
    limit = Number(url.searchParams.get("limit") ?? 1000);
  values = values.slice(offset, offset + limit);
  return respond(
    response,
    request.headers.accept?.includes("vnd.pgrst.object")
      ? (values[0] ?? null)
      : values,
  );
}
function concernRow(c, role) {
  return {
    id: c.id,
    xmin: String(c.version),
    account_id: c.accountId,
    submitted_by: c.submittedBy ?? ids.client,
    category: c.category,
    subject: c.subject,
    description: c.description,
    status: c.status,
    admin_response: c.response,
    created_at: c.createdAt,
    reviewed_at: c.reviewedAt,
    repair_dispatched_at: c.ticketId ? now : null,
    latitude: c.latitude ?? null,
    longitude: c.longitude ?? null,
    location_note: c.locationNote ?? null,
    service_accounts: {
      account_number: c.accountNumber,
      holder_name: c.holderName,
    },
    repair_tickets:
      c.ticketId &&
      (role !== "staff" ||
        state.tickets.some(
          (t) => t.id === c.ticketId && t.assignedToUserId === ids.staff,
        ))
        ? [{ id: c.ticketId }]
        : [],
  };
}
function ticketRow(t) {
  return {
    id: t.id,
    xmin: String(t.version),
    concern_id: t.concernId,
    status: t.status,
    assigned_to: t.assignedTo,
    assigned_to_user_id: t.assignedToUserId,
    latest_update: t.latestUpdate,
    updated_at: t.updatedAt,
    service_concerns: {
      account_id: ids.account,
      subject: t.subject,
      service_accounts: { account_number: t.accountNumber },
    },
  };
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
    return respond(response, {
      ok: true,
      legacyApiRequests: state.legacyApiRequests,
    });
  }
  if (url.pathname === "/health") return respond(response, { ok: true });
  if (url.pathname === "/__test/state") return respond(response, state);
  let role = roleFor(request);
  if (url.pathname === "/rest/v1/rpc/wd_staff_invitation") {
    const i = state.staffInvitations.find(
      (i) => i.token === body.p_token && i.status === "Pending",
    );
    return i
      ? respond(response, { email: i.email, displayName: i.display_name })
      : fail(response, "Invalid invitation", 422);
  }
  if (url.pathname === "/rest/v1/rpc/client_registration_approval_available")
    return respond(response, true);
  if (url.pathname === "/auth/v1/signup") {
    if (
      !["client_signup_v1", "staff_invite_v1"].includes(
        body.data?.registration_source,
      ) ||
      (body.data.registration_source === "client_signup_v1" &&
        !body.data.display_name) ||
      (body.data.registration_source === "client_signup_v1" &&
        !body.data.service_address)
    )
      return fail(response, "Registration details required", 422);
    return respond(response, { user: user("client"), session: null });
  }
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
  const active =
    !state.revoked.includes(role) &&
    !state.registrations.some(
      (r) => r.userId === ids[role] && r.status === "Pending",
    );
  if (url.pathname.endsWith("/client_registrations"))
    return rows(
      request,
      response,
      state.registrations
        .filter((r) => role === "admin" || r.userId === ids[role])
        .filter(
          (r) => !url.searchParams.get("status") || r.status === "Pending",
        )
        .map((r) => ({
          user_id: r.userId,
          full_name: r.fullName,
          service_address: r.serviceAddress,
          email: r.email,
          status: r.status,
          submitted_at: r.submittedAt,
          email_confirmed_at: r.emailConfirmedAt,
        })),
      url,
    );
  if (!active && !url.pathname.endsWith("/profiles"))
    return fail(response, "Inactive profile");
  if (url.pathname.startsWith("/api/")) {
    state.legacyApiRequests++;
    return fail(response, "Legacy API fixture disabled", 503);
  }
  const table = url.pathname.split("/").pop();
  if (table === "approve_client_registration") {
    if (role !== "admin") return fail(response, "Admin only");
    if (state.failNextWrite) {
      state.failNextWrite = false;
      return fail(response, "Simulated approval failure", 503);
    }
    const registration = state.registrations.find(
      (r) => r.userId === body.registration_user_id,
    );
    if (!registration) return fail(response, "Not found", 404);
    if (registration.status !== "Approved") {
      registration.status = "Approved";
      state.clientAccountId = ids.other;
      state.accounts.push({
        id: ids.other,
        accountNumber: "MWD-001250",
        holderName: registration.fullName,
        serviceAddress: registration.serviceAddress,
        active: true,
      });
    }
    return respond(response, [{ account_number: "MWD-001250" }]);
  }

  if (table === "wd_staff_directory")
    return respond(response, [
      {
        userId: ids.admin,
        displayName: "QA Admin",
        role: "admin",
        active: true,
        email: "admin@example.test",
      },
      {
        userId: ids.staff,
        displayName: "QA Staff",
        role: "staff",
        active: !state.revoked.includes("staff"),
        email: "staff@example.test",
      },
    ]);
  if (table === "staff_invitations")
    return rows(
      request,
      response,
      role === "admin" ? state.staffInvitations : [],
      url,
    );
  if (table === "wd_staff_invite") {
    if (role !== "admin") return fail(response, "Admin required");
    const id = crypto.randomUUID();
    const token = crypto.randomUUID();
    state.staffInvitations.push({
      id,
      token,
      email: body.p_email,
      display_name: body.p_display_name,
      status: "Pending",
      expires_at: "2026-12-04T08:00:00Z",
      invited_at: now,
    });
    return respond(response, { id, token, email: body.p_email });
  }
  if (table === "wd_staff_access") {
    if (role !== "admin") return fail(response, "Admin required");
    state.revoked = state.revoked.filter((r) => r !== "staff");
    if (!body.p_active) state.revoked.push("staff");
    return respond(response, { userId: body.p_user_id, active: body.p_active });
  }
  if (table === "wd_staff_revoke_invite") {
    if (role !== "admin") return fail(response, "Admin required");
    const i = state.staffInvitations.find((i) => i.id === body.p_id);
    if (i) i.status = "Revoked";
    return respond(response, { id: body.p_id });
  }
  if (table === "profiles") {
    const own = {
      user_id: ids[role],
      display_name: `QA ${role[0].toUpperCase() + role.slice(1)}`,
      role: role === "other" ? "client" : role,
      active: true,
    };
    const values = !active
      ? []
      : role === "admin"
        ? [
            own,
            {
              user_id: ids.staff,
              display_name: "QA Staff",
              role: "staff",
              active: true,
            },
          ]
        : [own];
    return rows(request, response, values, url);
  }
  if (table === "account_access")
    return rows(
      request,
      response,
      state.unlinked || role === "other"
        ? []
        : [
            {
              account_id: state.clientAccountId ?? ids.account,
              user_id: ids[role],
              active: true,
            },
          ],
      url,
    );
  if (url.pathname.startsWith("/rest/v1/rpc/")) {
    if (table.startsWith("wd_billing_")) {
      if (!state.billingAvailable)
        return respond(
          response,
          { code: "PGRST202", message: "Billing setup missing" },
          404,
        );
      if (table === "wd_billing_refresh")
        return respond(response, { asOf: "2026-11-27" });
      if (table === "wd_billing_status")
        return respond(response, { scheduleActive: true });
      if (role !== "admin" && table !== "wd_billing_confirm_payment")
        return fail(response, "Admin required");
      if (state.failNextWrite) {
        state.failNextWrite = false;
        return fail(response, "Simulated save failure", 503);
      }
      if (table === "wd_billing_set_plan") {
        const p = {
          account_id: body.p_account_id,
          monthly_amount: body.p_monthly_amount,
          enabled: body.p_enabled,
          next_issue_date: body.p_release_date,
        };
        state.billingPlans = state.billingPlans.filter(
          (p) => p.account_id !== body.p_account_id,
        );
        state.billingPlans.push(p);
        return respond(response, p);
      }
      if (table === "wd_billing_create_bill") {
        const existing = state.bills.find(
          (b) => b.requestId === body.p_request_id,
        );
        if (existing) return respond(response, { id: existing.id });
        const b = {
          id: crypto.randomUUID(),
          requestId: body.p_request_id,
          billNumber: `MWD-202611-${1000000000 + state.bills.length}`,
          accountNumber: account.accountNumber,
          periodStart: "2026-11-01",
          periodEnd: "2026-11-30",
          dueDate: body.p_due_date,
          releaseDate: body.p_release_date,
          amountDue: body.p_amount,
          paid: "0.00",
          remaining: body.p_amount,
        };
        state.bills.push(b);
        return respond(response, { id: b.id });
      }
      if (table === "wd_billing_confirm_payment") {
        const existing = state.payments.find(
          (p) => p.requestId === body.p_request_id,
        );
        if (existing) return respond(response, { id: existing.id });
        const b = state.bills.find((b) => b.id === body.p_bill_id);
        if (!b) return fail(response, "Bill unavailable", 404);
        const paid = state.payments
          .filter((p) => (p.billId ?? ids.bill) === b.id)
          .reduce((n, p) => n + Number(p.amountPaid), 0);
        if (Number(body.p_amount) > Number(b.amountDue) - paid)
          return respond(response, { code: "22023" }, 400);
        const p = {
          id: crypto.randomUUID(),
          requestId: body.p_request_id,
          billId: b.id,
          receiptReference: String(1000000000 + state.payments.length),
          billNumber: b.billNumber,
          accountNumber: b.accountNumber,
          paymentDate: body.p_payment_date,
          amountPaid: body.p_amount,
          verifiedAt: now,
        };
        state.payments.push(p);
        return respond(response, { id: p.id });
      }
      return fail(response, "Unknown billing function", 404);
    }
    if (!state.workflowAvailable)
      return respond(
        response,
        { code: "PGRST202", message: "Web workflow function missing" },
        404,
      );
    if (table === "wd_web_ticket_history") {
      const t = state.tickets.find((t) => t.id === body.p_ticket_id);
      if (!t || (role === "staff" && t.assignedToUserId !== ids.staff))
        return fail(response, "Ticket unavailable", 403);
      return respond(response, t.history);
    }
    if (table !== "wd_web_workflow") return fail(response, "Unknown RPC", 404);
    if (state.failNextWrite) {
      state.failNextWrite = false;
      return fail(response, "Simulated test save failure", 503);
    }
    if (!["admin", "staff"].includes(role))
      return fail(response, "Office required");
    const input = body.p_payload;
    if (body.p_action === "intake") {
      const existing = state.concerns.find((c) => c.id === body.p_id);
      if (existing) return respond(response, { id: existing.id });
      const c = {
        id: body.p_id,
        accountId: input.accountId,
        accountNumber: account.accountNumber,
        holderName: account.holderName,
        category: input.category,
        subject: input.subject,
        description: input.description,
        status: "Submitted",
        response: null,
        createdAt: now,
        reviewedAt: null,
        ticketId: null,
        version: 1,
        latitude: input.latitude,
        longitude: input.longitude,
        locationNote: input.locationNote,
        submittedBy: ids[role],
      };
      state.concerns.push(c);
      return respond(response, { id: c.id });
    }
    if (body.p_action === "review" || body.p_action === "dispatch") {
      const c = state.concerns.find((c) => c.id === body.p_id);
      if (!c) return fail(response, "Concern unavailable", 404);
      if (body.p_version !== c.version)
        return respond(
          response,
          { code: "40001", message: "Record changed" },
          409,
        );
      if (body.p_action === "review") {
        if (c.ticketId || ["Closed", "Resolved"].includes(c.status))
          return respond(response, { code: "40001" }, 409);
        Object.assign(c, {
          status: input.status,
          response: input.response,
          reviewedAt: now,
          version: c.version + 1,
        });
        return respond(response, { id: c.id });
      }
      if (role !== "admin") return fail(response, "Admin required");
      if (c.ticketId || c.status !== "Under review")
        return respond(response, { code: "40001" }, 409);
      const t = {
        id: crypto.randomUUID(),
        concernId: c.id,
        accountNumber: c.accountNumber,
        subject: c.subject,
        status: "Open",
        assignedTo: null,
        assignedToUserId: null,
        latestUpdate: input.note,
        updatedAt: now,
        version: 1,
        history: [
          {
            id: 1,
            status: "Open",
            note: input.note,
            changedBy: "QA Admin",
            assignedTo: null,
            changedAt: now,
          },
        ],
      };
      c.ticketId = t.id;
      c.version++;
      state.tickets.push(t);
      return respond(response, { id: t.id });
    }
    if (body.p_action === "update_ticket") {
      const t = state.tickets.find((t) => t.id === body.p_id);
      if (
        !t ||
        (role === "staff" &&
          (t.assignedToUserId !== ids.staff ||
            input.assignedToUserId !== ids.staff))
      )
        return fail(response, "Ticket unavailable", 403);
      if (body.p_version !== t.version)
        return respond(response, { code: "40001" }, 409);
      const transitions = {
        Open: ["Open", "Assigned"],
        Assigned: ["Assigned", "In progress", "Resolved"],
        "In progress": ["In progress", "Completed", "Resolved"],
        Completed: ["Completed", "In progress", "Resolved"],
      };
      if (!transitions[t.status]?.includes(input.status))
        return fail(response, "Invalid ticket transition", 400);
      Object.assign(t, {
        status: input.status,
        assignedToUserId: input.assignedToUserId,
        assignedTo: input.assignedToUserId ? "QA Staff" : null,
        latestUpdate: input.note,
        version: t.version + 1,
      });
      t.history.push({
        id: t.history.length + 1,
        status: t.status,
        note: input.note,
        changedBy: role === "admin" ? "QA Admin" : "QA Staff",
        assignedTo: t.assignedTo,
        changedAt: now,
      });
      if (t.status === "Resolved") {
        const c = state.concerns.find((c) => c.id === t.concernId);
        c.status = "Resolved";
        c.response = input.note;
        c.version++;
      }
      return respond(response, { id: t.id });
    }
    return fail(response, "Unsupported workflow", 422);
  }
  if (!url.pathname.startsWith("/rest/v1/"))
    return fail(response, "Unknown fixture route", 404);
  if (
    request.method !== "GET" &&
    request.method !== "HEAD" &&
    state.failNextWrite
  ) {
    state.failNextWrite = false;
    return fail(response, "Simulated test service failure", 503);
  }
  if (table === "service_accounts") {
    let values = state.accounts;
    if (request.method === "POST") {
      const saved = {
        id: crypto.randomUUID(),
        accountNumber: body.account_number,
        holderName: body.holder_name,
        serviceAddress: body.service_address,
        active: true,
      };
      state.accounts.push(saved);
      values = [saved];
    }
    return rows(
      request,
      response,
      values.map((a) => ({
        id: a.id,
        account_number: a.accountNumber,
        holder_name: a.holderName,
        service_address: a.serviceAddress,
        active: a.active,
      })),
      url,
    );
  }
  if (table === "billing_plans")
    return rows(
      request,
      response,
      role === "admin" ? state.billingPlans : [],
      url,
    );
  if (table === "bills") {
    let values = state.bills;
    if (role === "client" || role === "other") {
      const today = new Intl.DateTimeFormat("en-CA", {
        timeZone: "Asia/Manila",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      }).format(new Date());
      values = values.filter((b) => !b.releaseDate || b.releaseDate <= today);
    }
    if (request.method === "POST") {
      const saved = {
        id: crypto.randomUUID(),
        billNumber: body.bill_number,
        accountNumber: account.accountNumber,
        periodStart: body.billing_period_start,
        periodEnd: body.billing_period_end,
        dueDate: body.due_date,
        amountDue: body.amount_due,
        paid: "0.00",
        remaining: body.amount_due,
      };
      state.bills.push(saved);
      values = [saved];
    }
    return rows(
      request,
      response,
      values.map((b) => ({
        id: b.id,
        account_id: ids.account,
        bill_number: b.billNumber,
        billing_period_start: b.periodStart,
        billing_period_end: b.periodEnd,
        release_date: b.releaseDate ?? "2026-11-26",
        due_date: b.dueDate,
        amount_due: b.amountDue,
        base_amount_due: b.baseAmount ?? b.amountDue,
        interest_amount: b.interestAmount ?? "0.00",
        interest_days: b.interestDays ?? 0,
        service_accounts: {
          account_number: b.accountNumber,
          holder_name: state.accounts.find(
            (a) => a.accountNumber === b.accountNumber,
          )?.holderName,
          service_address: state.accounts.find(
            (a) => a.accountNumber === b.accountNumber,
          )?.serviceAddress,
        },
      })),
      url,
    );
  }
  if (table === "offline_payments") {
    let values = state.payments;
    if (request.method === "POST") {
      const p = {
        billId: body.bill_id,
        receiptReference: body.receipt_reference,
        billNumber: bill.billNumber,
        accountNumber: account.accountNumber,
        paymentDate: body.payment_date,
        amountPaid: body.amount_paid,
        verifiedAt: now,
      };
      state.payments.push(p);
      values = [p];
    }
    return rows(
      request,
      response,
      values.map((p, i) => ({
        id: p.id ?? `qa-${i}`,
        bill_id: p.billId ?? ids.bill,
        receipt_reference: p.receiptReference,
        payment_date: p.paymentDate,
        amount_paid: p.amountPaid,
        verified_at: p.verifiedAt,
        bills: {
          bill_number: p.billNumber,
          account_id: ids.account,
          service_accounts: { account_number: p.accountNumber },
        },
      })),
      url,
    );
  }
  if (table === "service_concerns") {
    let values = state.concerns;
    if (request.method === "POST") {
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
        latitude: body.latitude ?? null,
        longitude: body.longitude ?? null,
        locationNote: body.location_note ?? null,
        submittedBy: ids[role],
      };
      state.concerns.push(c);
      values = [c];
    }
    return rows(
      request,
      response,
      values.map((c) => concernRow(c, role)),
      url,
    );
  }
  if (table === "repair_tickets")
    return rows(
      request,
      response,
      state.tickets
        .filter((t) => role !== "staff" || t.assignedToUserId === ids.staff)
        .map(ticketRow),
      url,
    );
  if (table === "ticket_status_history")
    return rows(
      request,
      response,
      state.tickets.flatMap((t) =>
        (t.history ?? []).map((h) => ({
          ...h,
          ticket_id: t.id,
          changed_by: h.changedBy === "QA Admin" ? ids.admin : ids.staff,
          changed_at: h.changedAt,
          assigned_to: h.assignedTo,
        })),
      ),
      url,
    );
  if (table === "announcements") {
    let values = state.notices.filter((n) => role === "admin" || n.published);
    if (request.method === "POST" || request.method === "PATCH") {
      // Match the column grants in the exported, verified production schema.
      // updated_at has a DB default and is UPDATE-only for authenticated users.
      const allowed = new Set([
        "title",
        "message",
        "published",
        "updated_by",
        request.method === "POST" ? "created_by" : "updated_at",
      ]);
      if (
        role !== "admin" ||
        Object.keys(body).some((key) => !allowed.has(key)) ||
        body.updated_by !== ids.admin ||
        (request.method === "POST" && body.created_by !== ids.admin)
      ) {
        return respond(
          response,
          {
            code: "42501",
            message: "permission denied for announcements write",
          },
          403,
        );
      }
      const id =
        url.searchParams.get("id")?.replace("eq.", "") ?? crypto.randomUUID();
      const saved = {
        id,
        title: body.title,
        message: body.message,
        published: body.published,
        updatedAt: body.updated_at ?? now,
      };
      state.notices = [...state.notices.filter((n) => n.id !== id), saved];
      values = [saved];
    }
    return rows(
      request,
      response,
      values.map((n) => ({ ...n, updated_at: n.updatedAt })),
      url,
    );
  }
  return rows(request, response, [], url);
}).listen(54339, "127.0.0.1", () =>
  process.stdout.write("Isolated Supabase fixtures ready on loopback:54339\n"),
);
