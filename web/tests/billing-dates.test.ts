import { describe, it, expect } from "vitest";
import { nextBillingDueDate } from "@/lib/billing-dates";
describe("monthly issue date plus three calendar days", () => {
  it.each([
    ["2026-11-27", "2026-12-01"],
    ["2026-11-28", "2026-12-01"],
    ["2026-11-29", "2026-12-31"],
    ["2027-02-28", "2027-03-03"],
    ["2028-02-28", "2028-03-02"],
    ["2026-12-31", "2027-01-31"],
  ])("%s defaults due date to %s", (today, due) =>
    expect(nextBillingDueDate(today)).toBe(due),
  );
});
