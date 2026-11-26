import { beforeEach, expect, it, vi } from "vitest";
const state = vi.hoisted(() => ({
  invite: {
    email: "invited@example.test",
    displayName: "Invited Staff",
  } as unknown,
  error: null as unknown,
  user: null as unknown,
  signup: vi.fn(),
  signout: vi.fn(),
}));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServer: async () => ({
    rpc: async () => ({ data: state.invite, error: state.error }),
    auth: {
      getUser: async () => ({ data: { user: state.user }, error: null }),
      signUp: state.signup,
      signOut: state.signout,
    },
  }),
}));
import { POST } from "@/app/api/auth/[action]/route";
function call(action: string, body: unknown) {
  return POST(
    new Request(`https://district.test/api/auth/${action}`, {
      method: "POST",
      headers: {
        origin: "https://district.test",
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    }),
    { params: Promise.resolve({ action }) },
  );
}
beforeEach(() => {
  state.invite = {
    email: "invited@example.test",
    displayName: "Invited Staff",
  };
  state.error = null;
  state.user = null;
  vi.clearAllMocks();
  state.signup.mockResolvedValue({ data: { session: null }, error: null });
});
it("binds signup to the invitation email and trusts no submitted Staff/Admin role", async () => {
  const response = await call("staff-signup", {
    token: "private-token",
    email: "attacker@example.test",
    role: "admin",
    password: "staff-password",
    confirm: "staff-password",
  });
  expect(response.status).toBe(200);
  expect(state.signup).toHaveBeenCalledWith({
    email: "invited@example.test",
    password: "staff-password",
    options: {
      emailRedirectTo: "https://district.test/auth/callback",
      data: {
        registration_source: "staff_invite_v1",
        staff_invite_token: "private-token",
      },
    },
  });
});
it("rejects expired tokens, mismatched passwords and signed-in users before signup", async () => {
  state.error = { code: "22023" };
  expect((await call("staff-signup", { token: "bad" })).status).toBe(422);
  state.error = null;
  expect(
    (
      await call("staff-signup", {
        token: "valid",
        password: "staff-password",
        confirm: "different",
      })
    ).status,
  ).toBe(422);
  state.user = { id: "existing" };
  expect(
    (
      await call("staff-signup", {
        token: "valid",
        password: "staff-password",
        confirm: "staff-password",
      })
    ).status,
  ).toBe(409);
  expect(state.signup).not.toHaveBeenCalled();
});
