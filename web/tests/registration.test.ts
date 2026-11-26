import { beforeEach, describe, expect, it, vi } from "vitest";
const state = vi.hoisted(() => ({
  ready: true,
  session: null as null | { access_token: string },
  signup: vi.fn(),
  signout: vi.fn(),
}));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServer: async () => ({
    rpc: async () => ({ data: state.ready, error: null }),
    auth: {
      signUp: state.signup,
      signOut: state.signout,
    },
  }),
}));
import { POST } from "@/app/api/auth/[action]/route";
import { allowOfficeRequest } from "@/lib/upstream-policy";
const valid = {
  email: "client@example.test",
  fullName: " New Client ",
  serviceAddress: " Maramag address ",
  password: "password123",
  confirm: "password123",
  role: "admin",
  accountNumber: "MWD-000001",
};
function signup(body: Record<string, unknown> = valid) {
  return POST(
    new Request("http://localhost:3000/api/auth/signup", {
      method: "POST",
      headers: {
        origin: "http://localhost:3000",
        host: "localhost:3000",
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    }),
    { params: Promise.resolve({ action: "signup" }) },
  );
}
describe("client signup", () => {
  beforeEach(() => {
    state.ready = true;
    state.session = null;
    vi.clearAllMocks();
    state.signup.mockImplementation(async () => ({
      data: { session: state.session },
      error: null,
    }));
    state.signout.mockResolvedValue({ error: null });
  });
  it("checks password confirmation and required service details before creating Auth users", async () => {
    for (const patch of [
      { confirm: "wrong" },
      { password: "short", confirm: "short" },
      { fullName: "" },
      { serviceAddress: "" },
      { email: "bad" },
    ]) {
      expect((await signup({ ...valid, ...patch })).status).toBe(422);
    }
    expect(state.signup).not.toHaveBeenCalled();
  });
  it("fails closed when automatic provisioning is not installed", async () => {
    state.ready = false;
    expect((await signup()).status).toBe(503);
    expect(state.signup).not.toHaveBeenCalled();
  });
  it("passes only client details to Supabase and requests email confirmation", async () => {
    const response = await signup();
    expect(response.status).toBe(200);
    expect((await response.json()).message).toContain("confirm registration");
    expect(state.signup).toHaveBeenCalledWith({
      email: valid.email,
      password: valid.password,
      options: {
        emailRedirectTo: "http://localhost:3000/auth/callback",
        data: {
          registration_source: "client_signup_v1",
          display_name: "New Client",
          service_address: "Maramag address",
        },
      },
    });
    expect(state.signout).not.toHaveBeenCalled();
  });
  it("clears an automatically issued signup session before returning to sign-in", async () => {
    state.session = { access_token: "isolated-test-token" };
    expect((await signup()).status).toBe(200);
    expect(state.signout).toHaveBeenCalledWith({ scope: "local" });
  });
  it("restricts registration review and approval to admins", () => {
    const path =
      "office/registrations/10000000-0000-4000-8000-000000000003/approve";
    expect(allowOfficeRequest("admin", "POST", path)).toBe(true);
    for (const role of ["staff", "client"] as const) {
      expect(allowOfficeRequest(role, "POST", path)).toBe(false);
      expect(allowOfficeRequest(role, "GET", "office/registrations")).toBe(
        false,
      );
    }
  });
  it("denies manual account creation even to an administrator", () => {
    expect(allowOfficeRequest("admin", "POST", "office/accounts")).toBe(false);
    expect(allowOfficeRequest("admin", "GET", "office/accounts")).toBe(true);
  });
});
