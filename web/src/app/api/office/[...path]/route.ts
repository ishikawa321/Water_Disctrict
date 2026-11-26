import { authenticate } from "@/lib/server/auth";
import { allowOfficeRequest } from "@/lib/upstream-policy";
import { officeRequest } from "@/lib/server/office";
import {
  errorResponse,
  HttpError,
  json,
  readBody,
  requireSameOrigin,
} from "@/lib/server/http";
async function handle(
  request: Request,
  context: { params: Promise<{ path: string[] }> },
) {
  try {
    const { supabase, profile } = await authenticate(["admin", "staff"]);
    const route = (await context.params).path.join("/");
    if (!allowOfficeRequest(profile.role, request.method, route))
      throw new HttpError(
        403,
        "Your role does not permit this operation.",
        "forbidden",
      );
    let input: Record<string, unknown> = {};
    if (request.method !== "GET") {
      requireSameOrigin(request);
      input = await readBody(request);
    }
    return json(
      await officeRequest(
        { supabase, profile },
        request.method,
        route,
        new URL(request.url).searchParams,
        input,
      ),
    );
  } catch (error) {
    return errorResponse(error);
  }
}
export const GET = handle;
export const POST = handle;
export const PUT = handle;
