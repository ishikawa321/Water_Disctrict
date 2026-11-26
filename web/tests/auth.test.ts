import { beforeEach, describe, expect, it, vi } from "vitest";
const state = vi.hoisted(() => ({
  user: {
    id: "verified-user",
    email: "client@example.test",
    user_metadata: { role: "admin" },
  },
  authError: null as unknown,
  profile: {
    user_id: "verified-user",
    display_name: "Consumer",
    role: "client",
    active: true,
  } as Record<string, unknown> | null,
  profileError: null as unknown,
  pending: false,
}));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServer: async () => ({
    auth: {
      getUser: async () => ({
        data: { user: state.authError ? null : state.user },
        error: state.authError,
      }),
    },
    from: (table: string) => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({
            data:
              table === "client_registrations"
                ? state.pending
                  ? { status: "Pending" }
                  : null
                : state.profile,
            error: state.profileError,
          }),
        }),
      }),
    }),
  }),
}));
import { authenticate } from "@/lib/server/auth";
describe("validated active identity", () => {
  beforeEach(() => {
    state.authError = null;
    state.pending = false;
    state.profileError = null;
    state.profile = {
      user_id: "verified-user",
      display_name: "Consumer",
      role: "client",
      active: true,
    };
  });
  it("ignores editable metadata and reads the active profile role", async () => {
    expect((await authenticate()).profile.role).toBe("client");
    await expect(authenticate(["admin"])).rejects.toMatchObject({
      status: 403,
      code: "forbidden",
    });
  });
  it.each([
    null,
    { user_id: "verified-user", role: "admin", active: false },
    { user_id: "verified-user", role: "owner", active: true },
  ])("rejects disabled, missing or unsupported profiles", async (profile) => {
    state.profile = profile;
    await expect(authenticate()).rejects.toMatchObject({
      status: 403,
      code: "access_lost",
    });
  });
  it("denies pending registrations until the profile is approved", async () => {
    state.profile = null;
    state.pending = true;
    await expect(authenticate()).rejects.toMatchObject({
      status: 403,
      code: "registration_pending",
    });
    state.profile = {
      user_id: "verified-user",
      display_name: "Consumer",
      role: "client",
      active: true,
    };
    expect((await authenticate()).profile.role).toBe("client");
  });
  it("distinguishes expired sessions from a temporary auth outage", async () => {
    state.authError = { status: 401 };
    await expect(authenticate()).rejects.toMatchObject({
      status: 401,
      code: "session_lost",
    });
    state.authError = { status: 503 };
    await expect(authenticate()).rejects.toMatchObject({
      status: 503,
      code: "dependency",
    });
  });
});
