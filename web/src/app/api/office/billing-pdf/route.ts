import { authenticate } from "@/lib/server/auth";
import {
  billingExportIds,
  billingExportRecords,
} from "@/lib/server/billing-export";
import { billingPdf } from "@/lib/server/billing-pdf";
import {
  errorResponse,
  readBody,
  requireSameOrigin,
  uuid,
} from "@/lib/server/http";
import { todayInManila } from "@/lib/format";
export const runtime = "nodejs";
async function handle(request: Request, single: boolean) {
  try {
    const { supabase, profile } = await authenticate(["admin", "staff"]);
    let ids: string[];
    if (single) ids = [uuid(new URL(request.url).searchParams.get("billId"))];
    else {
      requireSameOrigin(request);
      ids = billingExportIds((await readBody(request, 65536)).billIds);
    }
    const records = await billingExportRecords(supabase, ids);
    const bytes = await billingPdf(records, {
      single,
      generatedAt: new Date(),
      preparedBy: profile.displayName,
    });
    const name = single
      ? `waterdistrict-bill-${records[0].billNumber.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 80)}.pdf`
      : `waterdistrict-billing-records-${todayInManila()}.pdf`;
    return new Response(new Uint8Array(bytes), {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `attachment; filename="${name}"`,
        "Cache-Control": "private, no-store, max-age=0",
        Vary: "Cookie",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch (error) {
    return errorResponse(error);
  }
}
export function GET(request: Request) {
  return handle(request, true);
}
export function POST(request: Request) {
  return handle(request, false);
}
