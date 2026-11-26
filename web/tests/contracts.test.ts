import { describe, expect, it } from "vitest";
import {
  balance,
  dateOnly,
  dateLabel,
  money,
  positiveMoney,
} from "@/lib/format";
import {
  canVisit,
  interruptionPrefix,
  noticeTitle,
  ticketChoices,
  clientRepairStates,
  clientRepairStatus,
} from "@/lib/policy";
import { allowOfficeRequest } from "@/lib/upstream-policy";
import { HttpError, requireSameOrigin, readBody } from "@/lib/server/http";

describe("money and calendar dates", () => {
  it("calculates exact cents, clamps overpayments and formats pesos", () => {
    expect(balance("0.30", ["0.10", "0.20"])).toEqual({
      paid: "0.30",
      remaining: "0.00",
    });
    expect(balance("100.00", ["120.00"]).remaining).toBe("0.00");
    expect(balance("9999999999.99", ["0.01"]).remaining).toBe("9999999999.98");
    expect(money("1234.50")).toBe("₱1,234.50");
  });
  it.each(["0", "-1", "1.001", "1e2", "1,000", "Infinity", "10000000000"])(
    "rejects unsupported amount %s",
    (value) => expect(() => positiveMoney(value)).toThrow(),
  );
  it("preserves date-only fields and rejects invalid or out-of-contract dates", () => {
    expect(dateOnly("2028-02-29")).toBe("2028-02-29");
    for (const date of [
      "2026-02-29",
      "2026-13-01",
      "1999-12-31",
      "2101-01-01",
      "2026-01-01T00:00:00Z",
    ])
      expect(() => dateOnly(date)).toThrow();
    expect(dateLabel("2026-11-26")).toContain("26");
  });
});
describe("role and route boundaries", () => {
  const id = "12345678-1234-4321-8123-123456789abc";
  it("denies admin pages and operations to Staff and consumers", () => {
    for (const section of ["accounts", "announcements", "staff"]) {
      expect(canVisit("staff", section)).toBe(false);
      expect(allowOfficeRequest("staff", "GET", `office/${section}`)).toBe(
        false,
      );
      expect(allowOfficeRequest("staff", "POST", `office/${section}`)).toBe(
        false,
      );
    }
    expect(canVisit("staff", "bills")).toBe(true);
    expect(canVisit("staff", "payments")).toBe(true);
    expect(allowOfficeRequest("staff", "GET", "office/bills")).toBe(true);
    expect(allowOfficeRequest("staff", "GET", "office/payments")).toBe(true);
    expect(allowOfficeRequest("staff", "POST", "office/payments")).toBe(true);
    expect(allowOfficeRequest("staff", "POST", "office/bills")).toBe(false);
    expect(allowOfficeRequest("staff", "POST", "admin/staff-invitations")).toBe(
      false,
    );
    expect(allowOfficeRequest("staff", "POST", "workflow/tickets")).toBe(false);
    expect(allowOfficeRequest("staff", "GET", "workflow/assignees")).toBe(
      false,
    );
    expect(allowOfficeRequest("client", "GET", "workflow/concerns")).toBe(
      false,
    );
    expect(allowOfficeRequest("client", "PUT", `workflow/tickets/${id}`)).toBe(
      false,
    );
  });
  it("permits only supported office contracts and leaves ownership validation to the API", () => {
    expect(allowOfficeRequest("staff", "PUT", `workflow/tickets/${id}`)).toBe(
      true,
    );
    expect(allowOfficeRequest("admin", "POST", "workflow/tickets")).toBe(true);
    expect(
      allowOfficeRequest("admin", "DELETE", `workflow/tickets/${id}`),
    ).toBe(false);
    for (const path of [
      "../admin/staff",
      "https://evil.example",
      "office/profiles",
      "office/accounts/delete",
    ])
      expect(allowOfficeRequest("admin", "GET", path)).toBe(false);
  });
  it("counts the exact interruption prefix toward the stored title", () => {
    expect(interruptionPrefix).toBe("[Service interruption] ");
    expect(
      (interruptionPrefix + "a".repeat(150 - interruptionPrefix.length)).length,
    ).toBe(150);
    expect(noticeTitle(`${interruptionPrefix}Water notice`)).toBe(
      "Water notice",
    );
    expect(noticeTitle("Other notice")).toBe("Other notice");
  });
});
describe("mutation request boundary", () => {
  it("rejects cross-origin and missing-origin writes", () => {
    expect(() =>
      requireSameOrigin(
        new Request("http://localhost:3100/api", {
          method: "POST",
          headers: {
            host: "127.0.0.1:3100",
            origin: "http://127.0.0.1:3100",
            "content-type": "application/json",
          },
        }),
      ),
    ).not.toThrow();
    expect(() =>
      requireSameOrigin(
        new Request("https://district.example/api", {
          method: "POST",
          headers: {
            origin: "https://evil.example",
            "content-type": "application/json",
          },
        }),
      ),
    ).toThrow(HttpError);
    expect(() =>
      requireSameOrigin(
        new Request("https://district.example/api", { method: "POST" }),
      ),
    ).toThrow(HttpError);
    expect(() =>
      requireSameOrigin(
        new Request("https://district.example/api", {
          method: "POST",
          headers: {
            origin: "https://district.example",
            "content-type": "application/json",
          },
        }),
      ),
    ).not.toThrow();
  });
  it("rejects malformed and oversized bodies", async () => {
    await expect(
      readBody(
        new Request("https://district.example", { method: "POST", body: "[]" }),
      ),
    ).rejects.toThrow();
    await expect(
      readBody(
        new Request("https://district.example", {
          method: "POST",
          body: JSON.stringify({ text: "x".repeat(33000) }),
        }),
      ),
    ).rejects.toThrow();
  });
});

describe("repair resolution", () => {
  it.each(["staff", "admin"] as const)(
    "allows %s to resolve assigned, active and legacy repairs",
    (role) => {
      for (const state of ["Assigned", "In progress", "Completed"]) {
        expect(ticketChoices(state, role)).toContain("Resolved");
        expect(ticketChoices(state, role)).not.toContain("Completed");
      }
      expect(ticketChoices("Resolved", role)).toEqual([]);
    },
  );
  it("uses four client steps and maps legacy completion to pending resolution", () => {
    expect(clientRepairStates).toEqual([
      "Open",
      "Assigned",
      "In progress",
      "Resolved",
    ]);
    expect(clientRepairStatus("Completed")).toBe("In progress");
    expect(clientRepairStatus("Resolved")).toBe("Resolved");
    expect(ticketChoices("Assigned", "client")).toEqual([]);
  });
});
