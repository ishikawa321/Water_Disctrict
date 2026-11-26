import "server-only";
import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js";
import type {
  Concern,
  Ticket,
  TicketDetails,
  History,
  Profile,
} from "@/lib/types";
import { balance, dateOnly, positiveMoney, todayInManila } from "@/lib/format";
import {
  categories,
  concernStates,
  repairStates,
  interruptionPrefix,
  relatedOne,
} from "@/lib/policy";
import { parseConcernLocation } from "@/lib/location";
import { HttpError, textField, uuid } from "./http";
import { paymentTotals } from "./consumer";

type Row = Record<string, unknown>;
type Context = { supabase: SupabaseClient; profile: Profile };
const accountFields = "id,account_number,holder_name,service_address,active";
const concernFields =
  "id,xmin,account_id,category,subject,description,status,admin_response,created_at,reviewed_at,repair_dispatched_at,latitude,longitude,location_note,service_accounts!inner(account_number,holder_name),repair_tickets(id)";
const ticketFields =
  "id,xmin,concern_id,status,assigned_to,assigned_to_user_id,latest_update,updated_at,service_concerns!inner(account_id,subject,service_accounts!inner(account_number))";
const noticeFields = "id,title,message,published,updated_at";
const paymentFields =
  "receipt_reference,payment_date,amount_paid,verified_at,bills(bill_number,service_accounts(account_number))";
function check(error: PostgrestError | null) {
  if (!error) return;
  if (error.code === "PGRST202")
    throw new HttpError(
      503,
      "Complete the one-time Supabase web workflow setup before saving this action. Your draft is retained.",
      "workflow_setup_required",
    );
  const status =
    error.code === "42501"
      ? 403
      : ["23505", "40001", "40P01"].includes(error.code)
        ? 409
        : ["23514", "23503", "22P02", "22023", "22003"].includes(error.code)
          ? 422
          : error.code === "P0002"
            ? 404
            : 503;
  throw new HttpError(
    status,
    status === 409
      ? "This record changed or already exists. Reload it before retrying."
      : status === 403
        ? "Your current account does not have permission for this record."
        : status === 422
          ? "The database rejected these values. Check the account, status, dates and required note."
          : status === 404
            ? "This record is unavailable or is not assigned to you."
            : "Supabase could not confirm the result. Refresh before retrying a save.",
    status === 409 ? "conflict" : error.code,
  );
}
function row(value: unknown): Row {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new HttpError(
      503,
      "Saved record fields could not be read. Refresh before retrying.",
    );
  return value as Row;
}
function rows(value: unknown): Row[] {
  if (!Array.isArray(value))
    throw new HttpError(
      503,
      "Saved records could not be read. Refresh to retry.",
    );
  return value.map(row);
}
function text(value: unknown): string {
  if (typeof value !== "string")
    throw new HttpError(503, "A saved record has incomplete fields.");
  return value;
}
function nested(value: unknown): Row {
  return relatedOne<Row>(value) ?? {};
}
// Union the newest 500 from each branch before applying the displayed limit;
// do not truncate a preliminary account lookup and lose matching repairs.
function matchingRows(
  results: { data: unknown; error: PostgrestError | null }[],
  dateField: string,
): Row[] {
  const unique = new Map<string, Row>();
  for (const result of results) {
    check(result.error);
    for (const record of rows(result.data)) unique.set(text(record.id), record);
  }
  return [...unique.values()]
    .sort(
      (a, b) =>
        Date.parse(text(b[dateField])) - Date.parse(text(a[dateField])) ||
        text(a.id).localeCompare(text(b.id)),
    )
    .slice(0, 500);
}
function nullableText(value: unknown): string | null {
  return value == null ? null : text(value);
}
function version(value: unknown): number {
  const number = typeof value === "string" ? Number(value) : value;
  if (
    typeof number !== "number" ||
    !Number.isInteger(number) ||
    number <= 0 ||
    number > 4294967295
  )
    throw new HttpError(
      503,
      "The saved record version is unavailable. Refresh before editing.",
    );
  return number;
}
function expectedVersion(value: unknown): number {
  if (
    typeof value !== "number" ||
    !Number.isInteger(value) ||
    value <= 0 ||
    value > 4294967295
  )
    throw new HttpError(422, "Reload the record before saving.", "validation");
  return value;
}
function inputDate(value: unknown): string {
  try {
    return dateOnly(textField(value, "Date", 10));
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(422, "Choose a valid calendar date.", "validation");
  }
}
function amount(value: unknown): string {
  try {
    if (typeof value !== "string" && typeof value !== "number")
      throw new Error();
    return positiveMoney(String(value));
  } catch {
    throw new HttpError(
      422,
      "Enter a positive amount with at most two decimal places.",
      "validation",
    );
  }
}
function searchPattern(query: URLSearchParams): string {
  return (
    "%" +
    (query.get("search")?.trim().slice(0, 150) ?? "").replace(
      /[%_\\]/g,
      "\\$&",
    ) +
    "%"
  );
}
function selectedState(
  query: URLSearchParams,
  allowed: readonly string[],
): string | null {
  const state = query.get("status");
  if (state && !allowed.includes(state))
    throw new HttpError(422, "Choose a valid status.");
  return state;
}
function account(record: Row) {
  return {
    id: text(record.id),
    accountNumber: text(record.account_number),
    holderName: text(record.holder_name),
    serviceAddress: text(record.service_address),
    active: record.active === true,
  };
}
function concern(record: Row): Concern {
  const service = nested(record.service_accounts);
  return {
    id: text(record.id),
    accountId: text(record.account_id),
    accountNumber:
      typeof service.account_number === "string"
        ? service.account_number
        : "Unavailable",
    holderName:
      typeof service.holder_name === "string"
        ? service.holder_name
        : "Unavailable",
    category: text(record.category),
    subject: text(record.subject),
    description: text(record.description),
    status: text(record.status),
    response: nullableText(record.admin_response),
    createdAt: text(record.created_at),
    reviewedAt: nullableText(record.reviewed_at),
    ticketId:
      typeof nested(record.repair_tickets).id === "string"
        ? text(nested(record.repair_tickets).id)
        : null,
    version: version(record.xmin),
    repairDispatchedAt: nullableText(record.repair_dispatched_at),
    latitude: typeof record.latitude === "number" ? record.latitude : null,
    longitude: typeof record.longitude === "number" ? record.longitude : null,
    locationNote: nullableText(record.location_note),
  };
}
function ticket(record: Row): Ticket {
  const c = nested(record.service_concerns),
    service = nested(c.service_accounts);
  return {
    id: text(record.id),
    concernId: text(record.concern_id),
    accountNumber:
      typeof service.account_number === "string"
        ? service.account_number
        : "Unavailable",
    subject: typeof c.subject === "string" ? c.subject : "Service repair",
    status: text(record.status),
    assignedTo: nullableText(record.assigned_to),
    assignedToUserId: nullableText(record.assigned_to_user_id),
    latestUpdate: text(record.latest_update),
    updatedAt: text(record.updated_at),
    version: version(record.xmin),
  };
}
function notice(record: Row) {
  return {
    id: text(record.id),
    title: text(record.title),
    message: text(record.message),
    published: record.published === true,
    updatedAt: text(record.updated_at),
  };
}
function payment(record: Row) {
  const b = nested(record.bills),
    a = nested(b.service_accounts);
  return {
    receiptReference: text(record.receipt_reference),
    billNumber:
      typeof b.bill_number === "string" ? b.bill_number : "Unavailable",
    accountNumber:
      typeof a.account_number === "string" ? a.account_number : "Unavailable",
    paymentDate: text(record.payment_date),
    amountPaid: String(record.amount_paid),
    verifiedAt: nullableText(record.verified_at),
  };
}
async function concernById(context: Context, id: string): Promise<Concern> {
  const { data, error } = await context.supabase
    .from("service_concerns")
    .select(concernFields)
    .eq("id", id)
    .maybeSingle();
  check(error);
  if (!data) throw new HttpError(404, "This concern is unavailable.");
  return concern(row(data));
}
async function ticketById(
  context: Context,
  id: string,
): Promise<TicketDetails> {
  let builder = context.supabase
    .from("repair_tickets")
    .select(ticketFields)
    .eq("id", id);
  if (context.profile.role === "staff")
    builder = builder.eq("assigned_to_user_id", context.profile.userId);
  const { data, error } = await builder.maybeSingle();
  check(error);
  if (!data)
    throw new HttpError(
      404,
      "This ticket is unavailable or is not assigned to you.",
    );
  const historyResult = await context.supabase.rpc("wd_web_ticket_history", {
    p_ticket_id: id,
  });
  let history: History[];
  if (historyResult.error?.code === "PGRST202") {
    const result = await context.supabase
      .from("ticket_status_history")
      .select("id,status,note,changed_by,assigned_to,changed_at")
      .eq("ticket_id", id)
      .order("id");
    check(result.error);
    history = rows(result.data).map((h) => ({
      id: Number(h.id),
      status: text(h.status),
      note: text(h.note),
      changedBy:
        h.changed_by === context.profile.userId
          ? context.profile.displayName
          : `District user ${text(h.changed_by)}`,
      assignedTo: nullableText(h.assigned_to),
      changedAt: text(h.changed_at),
    }));
  } else {
    check(historyResult.error);
    history = rows(historyResult.data).map((h) => ({
      id: Number(h.id),
      status: text(h.status),
      note: text(h.note),
      changedBy: text(h.changedBy),
      assignedTo: nullableText(h.assignedTo),
      changedAt: text(h.changedAt),
    }));
  }
  return { ticket: ticket(row(data)), history };
}
async function workflow(
  context: Context,
  action: string,
  id: string,
  recordVersion: number | null,
  payload: Row,
): Promise<string> {
  const { data, error } = await context.supabase.rpc("wd_web_workflow", {
    p_action: action,
    p_id: id,
    p_version: recordVersion,
    p_payload: payload,
  });
  check(error);
  return uuid(row(data).id);
}

export async function officeRequest(
  context: Context,
  method: string,
  route: string,
  query: URLSearchParams,
  input: Row,
): Promise<unknown> {
  const { supabase, profile } = context;
  if (route === "workflow/capabilities")
    return { concernLocation: true, storage: "supabase" };
  if (route === "office/summary") {
    const results = await Promise.all([
      supabase
        .from("service_concerns")
        .select("id", { head: true, count: "exact" })
        .in("status", ["Submitted", "Under review"]),
      supabase
        .from("repair_tickets")
        .select("id", { head: true, count: "exact" })
        .in("status", ["Open", "Assigned", "In progress"]),
    ]);
    for (const result of results) {
      check(result.error);
      if (typeof result.count !== "number")
        throw new HttpError(
          503,
          "Exact overview counts could not be loaded. Refresh to retry.",
        );
    }
    return {
      pendingConcerns: results[0].count,
      activeRepairs: results[1].count,
    };
  }
  if (route === "admin/staff" || route === "workflow/assignees") {
    let builder = supabase
      .from("profiles")
      .select("user_id,display_name,role")
      .eq("active", true);
    builder =
      route === "workflow/assignees"
        ? builder.eq("role", "staff")
        : builder.in("role", ["admin", "staff"]);
    const { data, error } = await builder.order("display_name");
    check(error);
    return rows(data).map((p) => ({
      userId: text(p.user_id),
      displayName: text(p.display_name),
      role: text(p.role),
    }));
  }
  if (route === "office/accounts" || route === "workflow/accounts") {
    if (method === "POST") {
      const { data, error } = await supabase
        .from("service_accounts")
        .insert({
          account_number: textField(input.accountNumber, "Account number", 80),
          holder_name: textField(input.holderName, "Holder name", 200),
          service_address: textField(
            input.serviceAddress,
            "Service address",
            500,
          ),
          active: true,
          updated_by: profile.userId,
        })
        .select(accountFields)
        .single();
      check(error);
      return account(row(data));
    }
    let builder = supabase.from("service_accounts").select(accountFields);
    if (route === "workflow/accounts") {
      builder = builder.eq("active", true);
      if (query.get("search")?.trim()) {
        const operand = JSON.stringify(searchPattern(query));
        builder = builder.or(
          `account_number.ilike.${operand},holder_name.ilike.${operand}`,
        );
      }
    }
    const { data, error } = await builder
      .order("account_number")
      .limit(route === "workflow/accounts" ? 200 : 1000);
    check(error);
    return rows(data).map(account);
  }
  if (route === "office/bills") {
    const fields =
      "id,bill_number,billing_period_start,billing_period_end,due_date,amount_due,service_accounts(account_number)";
    let records: Row[];
    if (method === "POST") {
      const start = inputDate(input.periodStart),
        end = inputDate(input.periodEnd),
        due = inputDate(input.dueDate);
      if (end < start)
        throw new HttpError(422, "Period end cannot precede period start.");
      const { data, error } = await supabase
        .from("bills")
        .insert({
          account_id: uuid(input.accountId),
          bill_number: textField(input.billNumber, "Bill number", 100),
          billing_period_start: start,
          billing_period_end: end,
          due_date: due,
          amount_due: amount(input.amountDue),
          created_by: profile.userId,
        })
        .select(fields)
        .single();
      check(error);
      records = [row(data)];
    } else {
      const { data, error } = await supabase
        .from("bills")
        .select(fields)
        .order("due_date", { ascending: false })
        .limit(1000);
      check(error);
      records = rows(data);
    }
    const totals = await paymentTotals(
      supabase,
      records.map((b) => text(b.id)),
    );
    const mapped = records.map((b) => ({
      id: text(b.id),
      billNumber: text(b.bill_number),
      accountNumber:
        typeof nested(b.service_accounts).account_number === "string"
          ? text(nested(b.service_accounts).account_number)
          : "Unavailable",
      periodStart: text(b.billing_period_start),
      periodEnd: text(b.billing_period_end),
      dueDate: text(b.due_date),
      amountDue: String(b.amount_due),
      ...balance(String(b.amount_due), [
        (totals.get(text(b.id)) ?? 0).toString(),
      ]),
    }));
    return method === "POST" ? mapped[0] : mapped;
  }
  if (route === "office/payments") {
    if (method === "POST") {
      const date = inputDate(input.paymentDate);
      if (input.verified !== true)
        throw new HttpError(
          422,
          "Confirm the offline payment has been verified.",
        );
      if (date > todayInManila())
        throw new HttpError(422, "Payment date cannot be in the future.");
      const { data, error } = await supabase
        .from("offline_payments")
        .insert({
          bill_id: uuid(input.billId),
          receipt_reference: textField(
            input.receiptReference,
            "Receipt/reference",
            150,
          ),
          payment_date: date,
          amount_paid: amount(input.amountPaid),
          verified_by: profile.userId,
        })
        .select(paymentFields)
        .single();
      check(error);
      return payment(row(data));
    }
    let builder = supabase.from("offline_payments").select(paymentFields);
    if (query.get("billId"))
      builder = builder.eq("bill_id", uuid(query.get("billId")));
    const { data, error } = await builder
      .order("payment_date", { ascending: false })
      .limit(1000);
    check(error);
    return rows(data).map(payment);
  }
  if (
    route === "office/announcements" ||
    route.startsWith("office/announcements/")
  ) {
    if (method === "GET") {
      const { data, error } = await supabase
        .from("announcements")
        .select(noticeFields)
        .order("updated_at", { ascending: false })
        .limit(1000);
      check(error);
      return rows(data).map(notice);
    }
    let title = textField(input.title, "Title", 150);
    if (title.startsWith(interruptionPrefix))
      title = title.slice(interruptionPrefix.length).trim();
    title = textField(
      (input.isInterruption === true ? interruptionPrefix : "") + title,
      "Full title including interruption marker",
      150,
    );
    if (
      typeof input.published !== "boolean" ||
      typeof input.isInterruption !== "boolean"
    )
      throw new HttpError(422, "Choose a valid publication state.");
    const values = {
      title,
      message: textField(input.message, "Message", 5000),
      published: input.published,
      updated_by: profile.userId,
      updated_at: new Date().toISOString(),
    };
    const builder =
      method === "POST"
        ? supabase
            .from("announcements")
            .insert({ ...values, created_by: profile.userId })
        : supabase
            .from("announcements")
            .update(values)
            .eq("id", uuid(route.split("/")[2]));
    const { data, error } = await builder.select(noticeFields).maybeSingle();
    check(error);
    if (!data) throw new HttpError(404, "This announcement is unavailable.");
    return notice(row(data));
  }
  if (route === "workflow/concerns" && method === "GET") {
    const state = selectedState(query, concernStates);
    const makeQuery = () => {
      let builder = supabase.from("service_concerns").select(concernFields);
      if (state) builder = builder.eq("status", state);
      return builder
        .order("created_at", { ascending: false })
        .order("id")
        .limit(500);
    };
    const results = query.get("search")?.trim()
      ? await Promise.all([
          makeQuery().ilike("subject", searchPattern(query)),
          makeQuery().ilike(
            "service_accounts.account_number",
            searchPattern(query),
          ),
        ])
      : [await makeQuery()];
    return matchingRows(results, "created_at").map(concern);
  }
  if (route === "workflow/concerns" && method === "POST") {
    const category = textField(input.category, "Category", 80);
    if (!(categories as readonly string[]).includes(category))
      throw new HttpError(422, "Choose a valid concern category.");
    let location;
    try {
      location = parseConcernLocation(input);
    } catch {
      throw new HttpError(
        422,
        "Choose valid coordinates together and a landmark of at most 300 characters.",
      );
    }
    const id = await workflow(context, "intake", uuid(input.requestId), null, {
      accountId: uuid(input.accountId),
      category,
      subject: textField(input.subject, "Subject", 150),
      description: textField(input.description, "Description", 3000),
      latitude: location?.latitude ?? null,
      longitude: location?.longitude ?? null,
      locationNote: location?.locationNote || null,
    });
    return concernById(context, id);
  }
  if (route.startsWith("workflow/concerns/")) {
    const id = uuid(route.split("/")[2]);
    if (method === "GET") return concernById(context, id);
    if (
      !["Under review", "Closed"].includes(String(input.status)) ||
      (input.response != null &&
        (typeof input.response !== "string" || input.response.length > 3000))
    )
      throw new HttpError(422, "Choose a valid review decision and response.");
    await workflow(context, "review", id, expectedVersion(input.version), {
      status: input.status,
      response: input.response ?? null,
    });
    return concernById(context, id);
  }
  if (route === "workflow/tickets" && method === "POST") {
    const id = await workflow(
      context,
      "dispatch",
      uuid(input.concernId),
      expectedVersion(input.concernVersion),
      { note: textField(input.note, "Initial repair note", 3000) },
    );
    return ticketById(context, id);
  }
  if (route === "workflow/tickets" && method === "GET") {
    const state = selectedState(query, repairStates);
    const makeQuery = () => {
      let builder = supabase.from("repair_tickets").select(ticketFields);
      if (profile.role === "staff")
        builder = builder.eq("assigned_to_user_id", profile.userId);
      if (state) builder = builder.eq("status", state);
      return builder
        .order("updated_at", { ascending: false })
        .order("id")
        .limit(500);
    };
    const results = query.get("search")?.trim()
      ? await Promise.all([
          makeQuery().ilike("service_concerns.subject", searchPattern(query)),
          makeQuery().ilike(
            "service_concerns.service_accounts.account_number",
            searchPattern(query),
          ),
        ])
      : [await makeQuery()];
    return matchingRows(results, "updated_at").map(ticket);
  }
  if (route.startsWith("workflow/tickets/")) {
    const id = uuid(route.split("/")[2]);
    if (method === "GET") return ticketById(context, id);
    if (!(repairStates as readonly string[]).includes(String(input.status)))
      throw new HttpError(422, "Choose a valid repair status.");
    await workflow(
      context,
      "update_ticket",
      id,
      expectedVersion(input.version),
      {
        status: input.status,
        assignedToUserId:
          input.assignedToUserId == null ? null : uuid(input.assignedToUserId),
        note: textField(input.note, "Update note", 3000),
      },
    );
    return ticketById(context, id);
  }
  throw new HttpError(404, "Unknown office operation.");
}
