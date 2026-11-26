import { test, expect, type Page } from "@playwright/test";
const fixture = "http://127.0.0.1:54339";
async function login(page: Page, role: string) {
  await page.goto("/login");
  await page.getByLabel("Email address").fill(`${role}@example.test`);
  await page.getByLabel("Password", { exact: true }).fill("test-password");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page).toHaveURL(
    new RegExp(role === "client" ? "/portal$" : "/office$"),
  );
}
test.beforeEach(async ({ request }) => {
  await request.post(`${fixture}/__test/reset`);
});

test("landing page is first and every primary demo button opens the app sign-in", async ({
  page,
}) => {
  const failedAssets: string[] = [];
  page.on("response", (response) => {
    if (response.url().includes("/landing/") && response.status() >= 400)
      failedAssets.push(response.url());
  });
  for (const selector of [
    "a.nav-cta",
    ".hero [data-open-demo]",
    "#explore [data-open-demo]",
  ]) {
    await page.goto("/");
    await expect(page.locator("#hero-title")).toContainText("A better flow.");
    await page.locator(selector).click();
    await expect(page).toHaveURL(/\/login$/);
    await expect(page.locator(".feedback.error")).toHaveCount(0);
    await expect(
      page.getByRole("heading", { name: "Welcome back" }),
    ).toBeVisible();
  }
  await page.getByRole("link", { name: "Back to the website" }).click();
  await expect(page).toHaveURL(/:3100\/$/);
  await page.locator("[data-open-tour]").click();
  await expect(page.locator("#demo-dialog")).toBeVisible();
  expect(failedAssets).toEqual([]);
});

test("landing demo restores an existing signed-in workspace", async ({
  page,
}) => {
  await login(page, "admin");
  await page.goto("/");
  await expect(page.locator("#hero-title")).toBeVisible();
  await page.locator(".hero [data-open-demo]").click();
  await expect(page).toHaveURL(/\/office$/);
  await expect(
    page.getByRole("heading", { name: /Welcome back, QA/ }),
  ).toBeVisible();
});

test("anonymous protected routes and API requests are denied", async ({
  page,
  request,
}) => {
  await page.goto("/office/concerns");
  await expect(page).toHaveURL(/\/login/);
  for (const url of [
    "/api/session",
    "/api/consumer/bills",
    "/api/office/office/accounts",
  ])
    expect((await request.get(url)).status()).toBe(401);
});
test("consumer sees linked billing, published notices and keeps a failed concern draft", async ({
  page,
  request,
}) => {
  await login(page, "client");
  await expect(
    page.getByRole("heading", { name: "Outstanding balance" }),
  ).toBeVisible();
  await expect(page.locator(".consumer-balance")).toContainText("₱350.00");
  await page.screenshot({
    path: test.info().outputPath("consumer-dashboard.png"),
    fullPage: true,
  });
  await page.getByRole("link", { name: "My bills", exact: true }).click();
  await expect(page.getByText("₱350.00").first()).toBeVisible();
  await page.getByRole("link", { name: /View payment history/ }).click();
  await expect(page.getByText("QA-RECEIPT-001")).toBeVisible();
  await page
    .getByRole("link", { name: "Announcements", exact: true })
    .first()
    .click();
  await expect(page.getByText("QA maintenance")).toBeVisible();
  await expect(page.getByText("QA private draft")).toHaveCount(0);
  await page
    .getByRole("link", { name: "Service concerns", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Submit concern", exact: true })
    .click();
  await page.getByLabel("Subject", { exact: true }).fill("Browser saved draft");
  await page
    .getByLabel("Description", { exact: true })
    .fill("Isolated browser acceptance report.");
  await request.post(`${fixture}/__test/scenario`, {
    data: { failNextWrite: true },
  });
  await page
    .locator("form")
    .getByRole("button", { name: "Submit concern", exact: true })
    .click();
  await expect(page.getByRole("alert")).toBeVisible();
  await expect(page.getByLabel("Subject", { exact: true })).toHaveValue(
    "Browser saved draft",
  );
  await page
    .getByRole("button", { name: "Close form", exact: true })
    .last()
    .click();
  await page
    .getByRole("button", { name: "Submit concern", exact: true })
    .first()
    .click();
  await expect(page.getByLabel("Subject", { exact: true })).toHaveValue(
    "Browser saved draft",
  );
  await page
    .locator("form")
    .getByRole("button", { name: "Submit concern", exact: true })
    .click();
  await expect(
    page
      .getByRole("status")
      .filter({ hasText: "Concern submitted and confirmed" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: /Browser saved draft/ }),
  ).toBeVisible();
});
test("Staff cannot visit or call Admin operations", async ({ page }) => {
  await login(page, "staff");
  await expect(
    page.getByRole("link", { name: "Billing", exact: true }),
  ).toHaveCount(0);
  expect((await page.request.get("/api/office/office/bills")).status()).toBe(
    403,
  );
  expect(
    (
      await page.request.post("/api/office/workflow/tickets", {
        data: {},
        headers: { Origin: "http://127.0.0.1:3100" },
      })
    ).status(),
  ).toBe(403);
  await page.goto("/office/accounts");
  await expect(page).toHaveURL(/\/office$/);
});
test("Admin review conflict retains response, then dispatches, assigns and Staff resolves", async ({
  page,
  request,
  browser,
}) => {
  await login(page, "admin");
  await page
    .getByRole("link", { name: "Service concerns", exact: true })
    .click();
  await page.getByRole("button", { name: /QA low pressure/ }).click();
  await page
    .getByLabel("Office response")
    .fill("Reviewed with district records.");
  await request.post(`${fixture}/__test/scenario`, {
    data: { bumpConcern: true },
  });
  await page.getByRole("button", { name: "Save review", exact: true }).click();
  await expect(
    page.getByRole("alert").filter({ hasText: "This record changed" }),
  ).toContainText("Reload");
  await expect(page.getByLabel("Office response")).toHaveValue(
    "Reviewed with district records.",
  );
  await page
    .getByRole("button", { name: "Reload form version", exact: true })
    .click();
  await expect(
    page.getByRole("status").filter({ hasText: "Latest form version" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Save review", exact: true }).click();
  await page.getByLabel("Initial repair note").fill("Inspection required.");
  await page
    .getByRole("button", { name: "Create repair ticket", exact: true })
    .click();
  await expect(page).toHaveURL(/\/office\/repairs\?ticketId=/);
  await page.getByLabel("Repair status").selectOption("Assigned");
  await page
    .getByLabel("Assigned Staff identity")
    .selectOption({ label: "QA Staff" });
  await page
    .getByLabel("Update note (required)")
    .fill("Assigned for inspection.");
  await page
    .getByRole("button", { name: "Save repair update", exact: true })
    .click();
  await expect(
    page.getByRole("status").filter({ hasText: "Repair update saved" }),
  ).toBeVisible();
  const staffContext = await browser.newContext();
  const staff = await staffContext.newPage();
  await login(staff, "staff");
  await staff
    .getByRole("link", { name: "Assigned repairs", exact: true })
    .click();
  await staff.getByRole("button", { name: /QA low pressure/ }).click();
  await staff.getByLabel("Repair status").selectOption("In progress");
  await staff.getByLabel("Update note (required)").fill("Inspection started.");
  await staff
    .getByRole("button", { name: "Save repair update", exact: true })
    .click();
  await expect(
    staff.getByRole("status").filter({ hasText: "Repair update saved" }),
  ).toBeVisible();
  await staff.getByLabel("Repair status").selectOption("Resolved");
  await staff
    .getByLabel("Update note (required)")
    .fill("Repair completed and verified.");
  await staff
    .getByRole("button", { name: "Save repair update", exact: true })
    .click();
  await expect(
    staff.getByRole("heading", { name: "Record an update" }),
  ).toHaveCount(0);
  await expect(staff.locator(".timeline li")).toHaveCount(4);
  await staffContext.close();
});
test("revoked profile clears the visible workspace", async ({
  page,
  request,
}) => {
  await login(page, "admin");
  await request.post(`${fixture}/__test/scenario`, {
    data: { revoked: ["admin"] },
  });
  await page
    .getByRole("button", { name: "Refresh access", exact: true })
    .click();
  await expect(page).toHaveURL(/\/login\?reason=access_lost/);
  await expect(page.getByRole("navigation", { name: "Workspace" })).toHaveCount(
    0,
  );
});
test("Admin creates accounts, bills, verified payments and notices using working forms", async ({
  page,
}) => {
  await login(page, "admin");
  await page
    .getByRole("link", { name: "Service accounts", exact: true })
    .click();
  await page.getByRole("button", { name: "New account", exact: true }).click();
  await page.getByLabel("Account number", { exact: true }).fill("QA-NEW-002");
  await page.getByLabel("Holder name", { exact: true }).fill("Isolated holder");
  await page
    .getByLabel("Service address", { exact: true })
    .fill("Isolated test address");
  await page
    .getByRole("button", { name: "Create account", exact: true })
    .click();
  await expect(
    page.getByRole("cell", { name: "QA-NEW-002", exact: true }),
  ).toBeVisible();
  await page.getByRole("link", { name: "Billing", exact: true }).click();
  await page.getByRole("button", { name: "New bill", exact: true }).click();
  await page
    .getByLabel("Active service account")
    .selectOption({ label: "QA-001 / QA Consumer" });
  await page.getByLabel("Bill number", { exact: true }).fill("QA-NEW-BILL");
  await page.getByLabel("District-computed amount (PHP)").fill("120.50");
  await page.getByLabel("Period start").fill("2026-11-01");
  await page.getByLabel("Period end").fill("2026-11-30");
  await page.getByLabel("Due date", { exact: true }).fill("2026-12-15");
  await page.getByRole("button", { name: "Create bill", exact: true }).click();
  await expect(
    page.getByRole("cell").filter({ hasText: "QA-NEW-BILL" }),
  ).toBeVisible();
  await page
    .getByRole("link", { name: "Verified payments", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Record payment", exact: true })
    .click();
  await page
    .getByRole("combobox", { name: "Bill", exact: true })
    .selectOption({ label: "QA-BILL-001 / QA-001 / ₱350.00 remaining" });
  await page
    .getByLabel("Receipt / reference", { exact: true })
    .fill("QA-NEW-RECEIPT");
  await page.getByLabel("Payment date", { exact: true }).fill("2026-11-25");
  await page.getByLabel("Verified amount (PHP)").fill("50.00");
  await page
    .getByLabel(
      "I have verified this offline payment against district records.",
    )
    .check();
  await page
    .getByRole("button", { name: "Record verified payment", exact: true })
    .click();
  await expect(
    page.getByRole("cell", { name: "QA-NEW-RECEIPT" }),
  ).toBeVisible();
  await page.getByRole("link", { name: "Announcements", exact: true }).click();
  await page.getByRole("button", { name: "New notice", exact: true }).click();
  await page.getByLabel("Title").fill("QA new notice");
  await page
    .getByLabel("Message", { exact: true })
    .fill("Isolated announcement.");
  await page.getByLabel("Service interruption notice").check();
  await page.getByLabel("Published — visible to consumers").check();
  await page.getByRole("button", { name: "Save notice", exact: true }).click();
  await expect(
    page
      .getByRole("status")
      .filter({ hasText: "Published notice saved." })
      .first(),
  ).toBeVisible();
  await expect(
    page.getByRole("button").filter({ hasText: "QA new notice" }),
  ).toHaveCount(1);
  await page.getByRole("button", { name: "Close editor", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Choose a notice" }),
  ).toBeVisible();
  await page.getByRole("button").filter({ hasText: "QA new notice" }).click();
  await expect(
    page.getByRole("heading", { name: "Edit notice", exact: true }),
  ).toBeVisible();
  await page.getByLabel("Message", { exact: true }).fill("Edited and saved.");
  await page.getByRole("button", { name: "Save notice", exact: true }).click();
  await expect(
    page.getByRole("button").filter({ hasText: "QA new notice" }),
  ).toHaveCount(1);
  await page.getByRole("button", { name: "New notice", exact: true }).click();
  await expect(page.getByLabel("Title")).toHaveValue("");
  await page
    .getByRole("link", { name: "Staff directory", exact: true })
    .click();
  await expect(
    page.getByRole("cell", { name: "QA Staff", exact: true }),
  ).toBeVisible();
});
test("unlinked consumers receive account guidance without seeing account records", async ({
  page,
  request,
}) => {
  await request.post(`${fixture}/__test/scenario`, {
    data: { unlinked: true },
  });
  await login(page, "client");
  await expect(
    page.getByRole("heading", { name: "Your account is not linked yet" }),
  ).toBeVisible();
  await page.getByRole("link", { name: "My bills", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Your account is not linked yet" }),
  ).toBeVisible();
  await expect(page.getByText("QA-BILL-001")).toHaveCount(0);
});
test("navigation and forms fit a narrow mobile viewport", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 640 });
  await login(page, "client");
  await page
    .getByRole("button", { name: "Open navigation", exact: true })
    .click();
  await page
    .getByRole("link", { name: "Service concerns", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Submit concern", exact: true })
    .click();
  await page.getByLabel("Subject", { exact: true }).fill("Mobile report");
  await page.screenshot({
    path: test.info().outputPath("mobile-concern.png"),
    fullPage: true,
  });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
});
