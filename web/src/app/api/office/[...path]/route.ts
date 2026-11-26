import { authenticate } from "@/lib/server/auth";
import { allowOfficeRequest } from "@/lib/upstream-policy";
import {
  errorResponse,
  HttpError,
  json,
  readBody,
  requireSameOrigin,
} from "@/lib/server/http";
async function forward(
  request: Request,
  context: { params: Promise<{ path: string[] }> },
) {
  try {
    const { supabase, profile } = await authenticate(["admin", "staff"]);
    const { path } = await context.params;
    const route = path.join("/");
    if (!allowOfficeRequest(profile.role, request.method, route))
      throw new HttpError(
        403,
        "Your role does not permit this operation.",
        "forbidden",
      );
    let payload: string | undefined;
    let input: Record<string, unknown> | undefined;
    if (request.method !== "GET") {
      requireSameOrigin(request);
      input = await readBody(request);
      payload = JSON.stringify(input);
    }
    const configured = process.env.WATERDISTRICT_API_URL;
    if (!configured)
      throw new HttpError(
        503,
        "The office service is not connected yet. Contact the system administrator.",
        "api_unconfigured",
      );
    const base = new URL(configured);
    if (
      base.username ||
      base.password ||
      (base.protocol !== "https:" &&
        !(
          process.env.NODE_ENV !== "production" &&
          base.protocol === "http:" &&
          ["localhost", "127.0.0.1"].includes(base.hostname)
        ))
    )
      throw new HttpError(
        503,
        "The office API address must use HTTPS.",
        "api_unconfigured",
      );
    const target = new URL(
      `${base.toString().replace(/\/$/, "")}/api/${route}`,
    );
    const query = new URL(request.url).searchParams;
    for (const key of ["search", "status", "billId"]) {
      const value = query.get(key);
      if (value) target.searchParams.set(key, value.slice(0, 200));
    }
    // getSession is used solely to retrieve a token AFTER getUser and the active profile check.
    const {
      data: { session },
    } = await supabase.auth.getSession();
    if (!session)
      throw new HttpError(
        401,
        "Your session has ended. Sign in again.",
        "session_lost",
      );
    if (
      request.method === "POST" &&
      route === "workflow/concerns" &&
      (input?.latitude != null ||
        input?.longitude != null ||
        input?.locationNote)
    ) {
      // An older API ignores unknown JSON fields. Check support before any write.
      let supported = false;
      try {
        const capabilities = await fetch(
          new URL(
            `${base.toString().replace(/\/$/, "")}/api/workflow/capabilities`,
          ),
          {
            cache: "no-store",
            redirect: "error",
            signal: AbortSignal.timeout(15000),
            headers: { Authorization: `Bearer ${session.access_token}` },
          },
        );
        supported =
          capabilities.ok &&
          (await capabilities.json()).concernLocation === true;
      } catch {
        /* Report an unconfirmed dependency without sending the concern. */
      }
      if (!supported)
        throw new HttpError(
          503,
          "The office service must be updated before saving an issue location. Your report has not been submitted; keep the draft and contact the system administrator.",
          "location_upgrade",
        );
    }
    let result: Response;
    try {
      result = await fetch(target, {
        method: request.method,
        body: payload,
        redirect: "error",
        cache: "no-store",
        signal: AbortSignal.timeout(25000),
        headers: {
          Authorization: `Bearer ${session.access_token}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
      });
    } catch {
      throw new HttpError(
        503,
        "The district API could not be reached. The saved result is unconfirmed; refresh before retrying.",
        "dependency",
      );
    }
    const body = await result.json().catch(() => null);
    if (!result.ok) {
      if (result.status === 401)
        throw new HttpError(
          401,
          "Your API session has ended. Sign in again.",
          "session_lost",
        );
      throw new HttpError(
        result.status,
        body?.detail ??
          (result.status === 403
            ? "The district API denied this operation. Refresh access and check your permitted role."
            : "The district API could not complete this operation. Refresh before retrying."),
        body?.code ?? "upstream",
      );
    }
    if (body === null)
      throw new HttpError(
        503,
        "The saved result could not be read. Refresh before retrying.",
        "dependency",
      );
    return json(body);
  } catch (error) {
    return errorResponse(error);
  }
}
export const GET = forward;
export const POST = forward;
export const PUT = forward;
