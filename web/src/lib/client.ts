"use client";
export class ClientError extends Error {
  constructor(
    message: string,
    public status: number,
    public code: string,
  ) {
    super(message);
  }
}
export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  let response: Response;
  try {
    response = await fetch(path, {
      ...init,
      cache: "no-store",
      headers: { "Content-Type": "application/json", ...init?.headers },
    });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") throw error;
    throw new ClientError(
      "The service could not be reached. Refresh before retrying a save.",
      503,
      "dependency",
    );
  }
  const body = await response.json().catch(() => null);
  if (!response.ok) {
    const code = body?.code ?? "operation_failed";
    if (code === "session_lost" || code === "access_lost")
      window.dispatchEvent(new Event("waterdistrict:access-lost"));
    if (code === "account_unlinked")
      window.dispatchEvent(new Event("waterdistrict:account-lost"));
    throw new ClientError(
      body?.detail ??
        (response.status === 409
          ? "This record changed. Reload it before saving."
          : "The operation could not be completed. Please retry."),
      response.status,
      code,
    );
  }
  return body as T;
}
export function save<T>(path: string, body: unknown, method = "POST") {
  return api<T>(path, { method, body: JSON.stringify(body) });
}
export function message(error: unknown) {
  return error instanceof Error
    ? error.message
    : "The operation could not be completed. Please retry.";
}
