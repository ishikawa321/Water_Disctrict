import { authenticate } from "@/lib/server/auth";
import { checkData, linkedAccount, pageNumber } from "@/lib/server/consumer";
import { categories, concernStates, repairStates } from "@/lib/policy";
import { balance } from "@/lib/format";
import {
  errorResponse,
  HttpError,
  json,
  readBody,
  requireSameOrigin,
  textField,
  uuid,
} from "@/lib/server/http";
const PAGE_SIZE = 30;
export async function GET(
  request: Request,
  context: { params: Promise<{ resource: string }> },
) {
  try {
    const { supabase, profile } = await authenticate(["client"]);
    const { resource } = await context.params;
    const query = new URL(request.url).searchParams;
    const page = pageNumber(query.get("page"));
    const start = page * PAGE_SIZE;
    if (resource === "announcements") {
      const { data, error } = await supabase
        .from("announcements")
        .select("id,title,message,published,updated_at")
        .eq("published", true)
        .order("updated_at", { ascending: false })
        .order("id")
        .range(start, start + PAGE_SIZE);
      checkData(error);
      return json({
        items: (data ?? [])
          .slice(0, PAGE_SIZE)
          .map((r) => ({
            id: r.id,
            title: r.title,
            message: r.message,
            published: r.published,
            updatedAt: r.updated_at,
          })),
        hasMore: (data?.length ?? 0) > PAGE_SIZE,
        page,
      });
    }
    const account = await linkedAccount(supabase, profile.userId);
    if (resource === "account") return json({ account });
    if (!account)
      throw new HttpError(
        403,
        "No active service account link is available. Contact authorized district personnel.",
        "account_unlinked",
      );
    if (resource === "bills") {
      const { data, error } = await supabase
        .from("bills")
        .select(
          "id,bill_number,billing_period_start,billing_period_end,due_date,amount_due,offline_payments(amount_paid)",
        )
        .eq("account_id", account.id)
        .order("due_date", { ascending: false })
        .order("id")
        .range(start, start + PAGE_SIZE);
      checkData(error);
      return json({
        items: (data ?? []).slice(0, PAGE_SIZE).map((r) => ({
          id: r.id,
          billNumber: r.bill_number,
          accountNumber: account.accountNumber,
          periodStart: r.billing_period_start,
          periodEnd: r.billing_period_end,
          dueDate: r.due_date,
          amountDue: String(r.amount_due),
          ...balance(
            String(r.amount_due),
            r.offline_payments.map((p) => String(p.amount_paid)),
          ),
        })),
        hasMore: (data?.length ?? 0) > PAGE_SIZE,
        page,
      });
    }
    if (resource === "payments") {
      const billId = uuid(query.get("billId"));
      const { data: bill, error: billError } = await supabase
        .from("bills")
        .select("id,bill_number")
        .eq("id", billId)
        .eq("account_id", account.id)
        .maybeSingle();
      checkData(billError);
      if (!bill)
        throw new HttpError(
          404,
          "This bill is unavailable for your linked account.",
        );
      const { data, error } = await supabase
        .from("offline_payments")
        .select("id,receipt_reference,payment_date,amount_paid,verified_at")
        .eq("bill_id", bill.id)
        .order("payment_date", { ascending: false })
        .order("id")
        .range(start, start + PAGE_SIZE);
      checkData(error);
      return json({
        items: (data ?? [])
          .slice(0, PAGE_SIZE)
          .map((r) => ({
            receiptReference: r.receipt_reference,
            billNumber: bill.bill_number,
            accountNumber: account.accountNumber,
            paymentDate: r.payment_date,
            amountPaid: String(r.amount_paid),
            verifiedAt: r.verified_at,
          })),
        hasMore: (data?.length ?? 0) > PAGE_SIZE,
        page,
      });
    }
    if (resource === "concerns") {
      let builder = supabase
        .from("service_concerns")
        .select(
          "id,account_id,category,subject,description,status,admin_response,created_at,reviewed_at,repair_tickets(id)",
        )
        .eq("account_id", account.id);
      if (query.get("id")) builder = builder.eq("id", uuid(query.get("id")));
      const status = query.get("status");
      if (status) {
        if (!(concernStates as readonly string[]).includes(status))
          throw new HttpError(422, "Choose a valid concern status.");
        builder = builder.eq("status", status);
      }
      const search = query.get("search")?.trim();
      if (search)
        builder = builder.ilike(
          "subject",
          `%${search.slice(0, 150).replace(/[%_\\]/g, "\\$&")}%`,
        );
      const { data, error } = await builder
        .order("created_at", { ascending: false })
        .order("id")
        .range(start, start + PAGE_SIZE);
      checkData(error);
      return json({
        items: (data ?? [])
          .slice(0, PAGE_SIZE)
          .map((r) => ({
            id: r.id,
            accountId: r.account_id,
            accountNumber: account.accountNumber,
            holderName: account.holderName,
            category: r.category,
            subject: r.subject,
            description: r.description,
            status: r.status,
            response: r.admin_response,
            createdAt: r.created_at,
            reviewedAt: r.reviewed_at,
            ticketId: r.repair_tickets[0]?.id ?? null,
            version: 0,
          })),
        hasMore: (data?.length ?? 0) > PAGE_SIZE,
        page,
      });
    }
    if (resource === "repairs") {
      let builder = supabase
        .from("repair_tickets")
        .select(
          "id,concern_id,status,assigned_to,latest_update,updated_at,service_concerns!inner(account_id,subject)",
        )
        .eq("service_concerns.account_id", account.id);
      if (query.get("id")) builder = builder.eq("id", uuid(query.get("id")));
      const search = query.get("search")?.trim();
      if (search)
        builder = builder.ilike(
          "service_concerns.subject",
          `%${search.slice(0, 150).replace(/[%_\\]/g, "\\$&")}%`,
        );
      const status = query.get("status");
      if (status) {
        if (!(repairStates as readonly string[]).includes(status))
          throw new HttpError(422, "Choose a valid repair status.");
        builder = builder.eq("status", status);
      }
      const { data, error } = await builder
        .order("updated_at", { ascending: false })
        .order("id")
        .range(start, start + PAGE_SIZE);
      checkData(error);
      return json({
        items: (data ?? [])
          .slice(0, PAGE_SIZE)
          .map((r) => ({
            id: r.id,
            concernId: r.concern_id,
            accountNumber: account.accountNumber,
            subject: (r.service_concerns as unknown as { subject: string })
              .subject,
            status: r.status,
            assignedTo: r.assigned_to,
            assignedToUserId: null,
            latestUpdate: r.latest_update,
            updatedAt: r.updated_at,
            version: 0,
          })),
        hasMore: (data?.length ?? 0) > PAGE_SIZE,
        page,
      });
    }
    throw new HttpError(404, "Unknown consumer service.");
  } catch (error) {
    return errorResponse(error);
  }
}
export async function POST(
  request: Request,
  context: { params: Promise<{ resource: string }> },
) {
  try {
    requireSameOrigin(request);
    const { supabase, profile } = await authenticate(["client"]);
    const { resource } = await context.params;
    if (resource !== "concerns")
      throw new HttpError(
        403,
        "Consumer access does not permit this operation.",
        "forbidden",
      );
    const account = await linkedAccount(supabase, profile.userId);
    if (!account?.active)
      throw new HttpError(
        403,
        "An active linked service account is required to submit a concern.",
        "account_unlinked",
      );
    const body = await readBody(request);
    const id = uuid(body.requestId);
    const category = textField(body.category, "Category", 80);
    if (!(categories as readonly string[]).includes(category))
      throw new HttpError(422, "Select a supported concern category.");
    const subject = textField(body.subject, "Subject", 150);
    const description = textField(body.description, "Description", 3000);
    const values = {
      id,
      account_id: account.id,
      submitted_by: profile.userId,
      category,
      subject,
      description,
    };
    // Reuse the request UUID on an uncertain retry; never upsert or overwrite a saved concern.
    const { data: existing, error: readError } = await supabase
      .from("service_concerns")
      .select("id,account_id,submitted_by,category,subject,description")
      .eq("id", id)
      .maybeSingle();
    checkData(readError);
    if (existing) {
      if (
        Object.entries(values).every(
          ([key, value]) => existing[key as keyof typeof existing] === value,
        )
      )
        return json({ id: existing.id });
      throw new HttpError(
        409,
        "This request was already saved with different details. Refresh before submitting another concern.",
        "conflict",
      );
    }
    const { data, error } = await supabase
      .from("service_concerns")
      .insert(values)
      .select("id")
      .single();
    checkData(error);
    if (!data)
      throw new HttpError(
        503,
        "The saved concern was not confirmed. Refresh before retrying.",
      );
    return json({ id: data.id }, 201);
  } catch (error) {
    return errorResponse(error);
  }
}
