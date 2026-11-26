import { afterEach, describe, expect, it, vi } from "vitest";
vi.mock("@/lib/server/auth", () => ({
  authenticate: async () => ({
    profile: { role: "staff" },
    supabase: {
      auth: {
        getSession: async () => ({
          data: { session: { access_token: "controlled-test-token" } },
        }),
      },
    },
  }),
}));
import { POST } from "@/app/api/office/[...path]/route";
describe("office location capability handshake", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });
  const submit = () =>
    POST(
      new Request("https://district.test/api/office/workflow/concerns", {
        method: "POST",
        headers: {
          origin: "https://district.test",
          "content-type": "application/json",
        },
        body: JSON.stringify({ latitude: 7.76, longitude: 125.0 }),
      }),
      { params: Promise.resolve({ path: ["workflow", "concerns"] }) },
    );
  it("does not submit a pinned report to an older API that could discard the pin", async () => {
    vi.stubEnv("WATERDISTRICT_API_URL", "https://api.example.test");
    const fetch = vi
      .fn()
      .mockResolvedValue(new Response("{}", { status: 404 }));
    vi.stubGlobal("fetch", fetch);
    const response = await submit();
    expect(response.status).toBe(503);
    expect((await response.json()).code).toBe("location_upgrade");
    expect(fetch).toHaveBeenCalledTimes(1);
    expect(String(fetch.mock.calls[0][0])).toContain("/workflow/capabilities");
  });
  it("forwards the location only after confirmed support using the caller token", async () => {
    vi.stubEnv("WATERDISTRICT_API_URL", "https://api.example.test");
    const fetch = vi
      .fn()
      .mockResolvedValueOnce(new Response('{"concernLocation":true}'))
      .mockResolvedValueOnce(new Response('{"id":"saved"}'));
    vi.stubGlobal("fetch", fetch);
    expect((await submit()).status).toBe(200);
    expect(fetch).toHaveBeenCalledTimes(2);
    expect(JSON.parse(fetch.mock.calls[1][1].body)).toEqual({
      latitude: 7.76,
      longitude: 125,
    });
    expect(fetch.mock.calls[1][1].headers.Authorization).toBe(
      "Bearer controlled-test-token",
    );
  });
});
