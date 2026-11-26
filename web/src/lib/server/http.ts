import "server-only";
import { NextResponse } from "next/server";
export class HttpError extends Error {
  constructor(
    public status: number,
    message: string,
    public code = "operation_failed",
  ) {
    super(message);
  }
}
export function json(value: unknown, status = 200) {
  return NextResponse.json(value, {
    status,
    headers: {
      "Cache-Control": "private, no-store, max-age=0",
      Vary: "Cookie",
    },
  });
}
export function errorResponse(error: unknown) {
  if (error instanceof HttpError)
    return json({ detail: error.message, code: error.code }, error.status);
  return json(
    {
      detail:
        "The service could not confirm the result. Refresh before retrying a save.",
      code: "dependency",
    },
    503,
  );
}
export function requireSameOrigin(request: Request) {
  const origin = request.headers.get("origin");
  const host = request.headers.get("host") ?? new URL(request.url).host;
  let source: URL | null = null;
  try {
    if (origin) source = new URL(origin);
  } catch {
    /* Invalid origin is denied below. */
  }
  if (
    !source ||
    source.host !== host ||
    !["https:", "http:"].includes(source.protocol) ||
    (process.env.NODE_ENV === "production" && source.protocol !== "https:")
  )
    throw new HttpError(
      403,
      "This request must come from this website.",
      "origin",
    );
  if (!request.headers.get("content-type")?.startsWith("application/json"))
    throw new HttpError(415, "Send a JSON request.");
}
export function publicOrigin(request: Request) {
  const url = new URL(request.url);
  const host = request.headers.get("host") ?? url.host;
  return `${process.env.NODE_ENV === "production" ? "https:" : url.protocol}//${host}`;
}
export async function readBody(
  request: Request,
): Promise<Record<string, unknown>> {
  if (Number(request.headers.get("content-length") ?? 0) > 32768)
    throw new HttpError(413, "The form is too large.");
  const raw = await request.text();
  if (raw.length > 32768) throw new HttpError(413, "The form is too large.");
  try {
    const body: unknown = JSON.parse(raw);
    if (!body || typeof body !== "object" || Array.isArray(body))
      throw new Error();
    return body as Record<string, unknown>;
  } catch {
    throw new HttpError(422, "The form could not be read.");
  }
}
export function textField(value: unknown, label: string, maximum: number) {
  if (
    typeof value !== "string" ||
    !value.trim() ||
    value.trim().length > maximum
  )
    throw new HttpError(
      422,
      `${label} is required and must be at most ${maximum} characters.`,
      "validation",
    );
  return value.trim();
}
export function uuid(value: unknown) {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    )
  )
    throw new HttpError(422, "Select a valid saved record.", "validation");
  return value;
}
