import { NextResponse } from "next/server";
import { createSupabaseServer } from "@/lib/supabase/server";
import { publicOrigin } from "@/lib/server/http";
export async function GET(request: Request) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  if (code) {
    const supabase = await createSupabaseServer();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error)
      return NextResponse.redirect(
        new URL(
          url.searchParams.get("next") === "/reset-password"
            ? "/reset-password"
            : "/app",
          publicOrigin(request),
        ),
      );
  }
  return NextResponse.redirect(
    new URL("/login?reason=recovery_expired", publicOrigin(request)),
  );
}
