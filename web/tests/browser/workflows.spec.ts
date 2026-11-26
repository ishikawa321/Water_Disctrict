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
test.afterEach(async ({ request }) => {
  const response = await request.get(`${fixture}/__test/state`);
  expect((await response.json()).legacyApiRequests).toBe(0);
});

test("monthly billing saves per-account amounts and confirmed full payment appears on the consumer balance", async ({
  page,
  request,
}) => {
  const state = await (await request.get(`${fixture}/__test/state`)).json();
  const savedBill = {
    ...state.bills[0],
    dueDate: "2026-11-24",
    baseAmount: "500.00",
    interestAmount: "15.00",
    interestDays: 3,
    amountDue: "515.00",
  };
  await request.post(`${fixture}/__test/scenario`, {
    data: { bills: [savedBill], payments: [] },
  });
  await login(page, "admin");
  await page.getByRole("link", { name: "Billing", exact: true }).click();
  await page
    .getByLabel("Monthly billing account")
    .selectOption({ label: "QA-001 / QA Consumer" });
  await page.getByLabel("Monthly amount (PHP)").fill("1000.00");
  await page
    .getByRole("button", { name: "Save monthly billing", exact: true })
    .click();
  await expect(
    page
      .getByRole("status")
      .filter({ hasText: "Monthly billing settings saved" }),
  ).toBeVisible();
  await expect(
    page.getByRole("cell", { name: "Enabled", exact: true }),
  ).toBeVisible();
  await page.screenshot({
    path: test.info().outputPath("monthly-billing-interest.png"),
    fullPage: true,
  });
  await page
    .getByRole("link", { name: "Verified payments", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Record payment", exact: true })
    .click();
  await page
    .getByRole("combobox", { name: "Bill", exact: true })
    .selectOption(savedBill.id);
  await page
    .getByRole("button", { name: "Use full remaining balance", exact: true })
    .click();
  await expect(page.getByLabel("Verified amount (PHP)")).toHaveValue("515.00");
  await page
    .getByLabel(
      "I have verified this offline payment against district records.",
    )
    .check();
  await request.post(`${fixture}/__test/scenario`, {
    data: { failNextWrite: true },
  });
  await page
    .getByRole("button", { name: "Confirm payment", exact: true })
    .click();
  await expect(page.locator(".feedback.error")).toBeVisible();
  await expect(page.getByLabel("Verified amount (PHP)")).toHaveValue("515.00");
  await page
    .getByRole("button", { name: "Confirm payment", exact: true })
    .click();
  await expect(
    page
      .getByRole("status")
      .filter({ hasText: "Payment confirmed. Reference:" }),
  ).toContainText("1000000000");
  await login(page, "client");
  await expect(page.locator(".consumer-balance")).toContainText("₱0.00");
  await page
    .getByRole("navigation", { name: "Workspace", exact: true })
    .getByRole("link", { name: "My bills", exact: true })
    .click();
  await expect(page).toHaveURL(/portal\/bills$/);
  await page.getByText("Billing details", { exact: true }).click();
  await expect(
    page.getByText("Daily interest (3 overdue days)", { exact: true }),
  ).toBeVisible();
  await expect(page.getByText("₱15.00", { exact: true })).toBeVisible();
  await page.screenshot({
    path: test.info().outputPath("consumer-settled-interest.png"),
    fullPage: true,
  });
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
  await page
    .getByRole("navigation", { name: "Workspace", exact: true })
    .getByRole("link", { name: "My bills", exact: true })
    .click();
  await expect(page).toHaveURL(/portal\/bills$/);
  await expect(page.getByText("₱350.00").first()).toBeVisible();
  await page.getByRole("link", { name: /View payment history/ }).click();
  await expect(page.getByText("QA-RECEIPT-001")).toBeVisible();
  await page
    .getByRole("link", { name: "Announcements", exact: true })
    .first()
    .click();
  await expect(page).toHaveURL(/portal\/announcements$/);
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
  await expect(page.locator(".feedback.error")).toBeVisible();
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
    page.locator(".feedback.error").filter({ hasText: "This record changed" }),
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
  await expect(page.getByLabel("Bill number", { exact: true })).toHaveCount(0);
  await page.getByLabel("District-computed amount (PHP)").fill("120.50");
  await expect(page.getByLabel("Period start")).toHaveCount(0);
  await expect(page.getByLabel("Period end")).toHaveCount(0);
  await page.getByLabel("Due date", { exact: true }).fill("2026-12-15");
  await page.getByRole("button", { name: "Create bill", exact: true }).click();
  await expect(
    page.getByRole("cell").filter({ hasText: "MWD-202611-1000000001" }),
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
  await expect(
    page.getByLabel("Receipt / reference", { exact: true }),
  ).toHaveCount(0);
  await page.getByLabel("Payment date", { exact: true }).fill("2026-11-25");
  await page.getByLabel("Verified amount (PHP)").fill("50.00");
  await page
    .getByLabel(
      "I have verified this offline payment against district records.",
    )
    .check();
  await page
    .getByRole("button", { name: "Confirm payment", exact: true })
    .click();
  await expect(page.getByRole("cell", { name: "1000000001" })).toBeVisible();
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
  await page
    .getByRole("navigation", { name: "Workspace", exact: true })
    .getByRole("link", { name: "My bills", exact: true })
    .click();
  await expect(page).toHaveURL(/portal\/bills$/);
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

// Location and payment checks use only the isolated loopback fixture.
async function stubTiles(page: Page) {
  await page.route("https://tile.openstreetmap.org/**", (route) =>
    route.fulfill({
      contentType: "image/png",
      body: Buffer.from(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jGZkAAAAASUVORK5CYII=",
        "base64",
      ),
    }),
  );
}
async function chooseCoordinates(
  page: Page,
  latitude: string,
  longitude: string,
  note: string,
) {
  const dialog = page.getByRole("dialog");
  await dialog.getByText("Enter coordinates manually", { exact: true }).click();
  await dialog.getByLabel("Latitude", { exact: true }).fill(latitude);
  await dialog.getByLabel("Longitude", { exact: true }).fill(longitude);
  await dialog
    .getByRole("button", { name: "Use coordinates", exact: true })
    .click();
  await dialog.getByLabel("Landmark / location note (optional)").fill(note);
  await dialog
    .getByRole("button", { name: "Confirm location", exact: true })
    .click();
}
test("consumer pins survive cancellation and a failed save, and saved maps are read-only", async ({
  page,
  request,
}) => {
  await stubTiles(page);
  await page.addInitScript(() => {
    let calls = 0;
    Object.defineProperty(window, "__gpsCalls", { get: () => calls });
    Object.defineProperty(navigator, "geolocation", {
      configurable: true,
      value: {
        getCurrentPosition: (
          _success: unknown,
          failure: (error: { code: number }) => void,
        ) => {
          calls++;
          failure({ code: 1 });
        },
      },
    });
  });
  await login(page, "client");
  await page.goto("/portal/concerns?new=1");
  await page
    .getByLabel("Subject", { exact: true })
    .fill("Pinned browser report");
  await page
    .getByLabel("Description", { exact: true })
    .fill("Issue near a test connection.");
  await page
    .getByRole("button", { name: "Choose location", exact: true })
    .click();
  await expect(page.locator(".leaflet-container")).toBeVisible();
  expect(await page.evaluate(() => Reflect.get(window, "__gpsCalls"))).toBe(0);
  await page
    .getByRole("button", { name: "Use my location", exact: true })
    .click();
  await expect(page.locator(".feedback.error")).toContainText(
    "permission was denied",
  );
  await chooseCoordinates(page, "7.7633", "125.0058", "Beside QA meter");
  await page
    .getByRole("button", { name: "Change location", exact: true })
    .click();
  const dialog = page.getByRole("dialog");
  await dialog
    .getByLabel("Landmark / location note (optional)")
    .fill("Cancelled change");
  await dialog.getByRole("button", { name: "Cancel", exact: true }).click();
  await expect(page.locator(".location-field")).toContainText(
    "Beside QA meter",
  );
  await expect(page.locator(".location-field")).not.toContainText(
    "Cancelled change",
  );
  await request.post(`${fixture}/__test/scenario`, {
    data: { failNextWrite: true },
  });
  await page
    .locator("form")
    .getByRole("button", { name: "Submit concern", exact: true })
    .click();
  await expect(page.locator(".feedback.error")).toBeVisible();
  await expect(page.locator(".location-field")).toContainText(
    "7.763300, 125.005800",
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
  await page
    .getByRole("button", { name: /QA-001.*Pinned browser report/ })
    .click();
  await expect(page.locator(".location-details")).toContainText(
    "Beside QA meter",
  );
  await page
    .getByRole("button", { name: "View location", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toContainText("read-only");
  await expect(
    page.getByRole("dialog").getByRole("button", { name: "Use my location" }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("dialog").getByRole("button", { name: "Confirm location" }),
  ).toHaveCount(0);
  await page
    .getByRole("button", { name: "Close location", exact: true })
    .click();
  await page.reload();
  await expect(page.locator(".record-list")).toContainText(
    "Pinned browser report",
  );
});
test("office retains a pinned draft before SQL setup, then saves and preserves it on review", async ({
  page,
  request,
}) => {
  await stubTiles(page);
  await login(page, "staff");
  await page.goto("/office/concerns");
  await page
    .getByRole("button", { name: "New office report", exact: true })
    .click();
  await page
    .getByLabel("Active service account")
    .selectOption({ label: "QA-001 / QA Consumer" });
  await page
    .getByLabel("Subject", { exact: true })
    .fill("Pinned office report");
  await page
    .getByLabel("Description", { exact: true })
    .fill("Pinned office report description.");
  await page
    .getByRole("button", { name: "Choose location", exact: true })
    .click();
  await chooseCoordinates(page, "7.76", "125.0", "Beside office meter");
  await request.post(`${fixture}/__test/scenario`, {
    data: { workflowAvailable: false },
  });
  await page
    .locator("form")
    .getByRole("button", { name: "Submit concern", exact: true })
    .click();
  await expect(page.locator(".feedback.error")).toContainText(
    "one-time Supabase",
  );
  await expect(page.locator(".record-list")).not.toContainText(
    "Pinned office report",
  );
  await expect(page.locator(".location-field")).toContainText(
    "Beside office meter",
  );
  await request.post(`${fixture}/__test/scenario`, {
    data: { workflowAvailable: true },
  });
  await page
    .locator("form")
    .getByRole("button", { name: "Submit concern", exact: true })
    .click();
  await expect(page.locator(".record-list")).toContainText(
    "Pinned office report",
  );
  await page
    .getByRole("button", { name: /QA-001.*Pinned office report/ })
    .click();
  await expect(page.locator(".location-details")).toContainText(
    "7.760000, 125.000000",
  );
  await page
    .getByLabel("Office response", { exact: true })
    .fill("Reviewed at saved location.");
  await page.getByRole("button", { name: "Save review", exact: true }).click();
  await expect(
    page.getByRole("status").filter({ hasText: /saved/i }).last(),
  ).toBeVisible();
  await expect(page.locator(".location-details")).toContainText(
    "Beside office meter",
  );
});
test("payment guidance shows bill references and latest notices follow publication date", async ({
  page,
  request,
}) => {
  await request.post(`${fixture}/__test/scenario`, {
    data: {
      notices: [
        {
          id: "60000000-0000-4000-8000-000000000001",
          title: "[Service interruption] Old maintenance",
          message: "Older published notice",
          published: true,
          updatedAt: "2026-11-24T08:00:00Z",
        },
        {
          id: "60000000-0000-4000-8000-000000000002",
          title: "New district update",
          message: "Newest published notice",
          published: true,
          updatedAt: "2026-11-26T08:00:00Z",
        },
      ],
    },
  });
  await login(page, "client");
  await expect(
    page.getByText("New district update", { exact: true }),
  ).toBeVisible();
  await expect(
    page.locator(".card").filter({
      has: page.getByRole("heading", {
        name: "Latest district notice",
        exact: true,
      }),
    }),
  ).not.toContainText("Old maintenance");
  await page
    .getByRole("button", { name: "Payment instructions", exact: true })
    .click();
  const dialog = page.getByRole("dialog");
  await expect(dialog).toContainText("QA-001");
  await expect(dialog).toContainText("QA-BILL-001");
  await expect(dialog).toContainText("after district verification");
  await page.keyboard.press("Escape");
  await expect(dialog).toHaveCount(0);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole("link", { name: /Report issue/ }).click();
  await expect(page.getByLabel("Subject", { exact: true })).toBeVisible();
  await stubTiles(page);
  await page
    .getByRole("button", { name: "Choose location", exact: true })
    .click();
  await expect(page.getByRole("dialog")).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  await page
    .getByRole("button", { name: "Place pin at map center", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Confirm location", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Remove location", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Choose location", exact: true }),
  ).toBeVisible();
});

test("GPS success stays editable, timeout and tile failures keep manual selection available", async ({
  page,
}) => {
  await page.route("https://tile.openstreetmap.org/**", (route) =>
    route.abort(),
  );
  await page.addInitScript(() => {
    let calls = 0;
    Object.defineProperty(navigator, "geolocation", {
      configurable: true,
      value: {
        getCurrentPosition: (
          success: (value: {
            coords: { latitude: number; longitude: number };
          }) => void,
          failure: (error: { code: number }) => void,
        ) => {
          if (calls++ === 0)
            success({ coords: { latitude: 7.77, longitude: 125.01 } });
          else failure({ code: 3 });
        },
      },
    });
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await login(page, "client");
  await page.goto("/portal/concerns?new=1");
  await page
    .getByRole("button", { name: "Choose location", exact: true })
    .click();
  const dialog = page.getByRole("dialog");
  await dialog
    .getByRole("button", { name: "Use my location", exact: true })
    .click();
  await expect(dialog).toContainText("7.770000, 125.010000");
  await expect(dialog).toContainText("may be approximate");
  await expect(dialog).toContainText("Map tiles could not load");
  await dialog
    .getByRole("button", { name: "Use my location", exact: true })
    .click();
  await expect(dialog.locator(".feedback.error")).toContainText("timed out");
  await expect(dialog).toContainText("7.770000, 125.010000");
  await dialog.getByRole("button", { name: "Retry map", exact: true }).click();
  await expect(dialog).toContainText("7.770000, 125.010000");
  await dialog
    .locator(".leaflet-container")
    .click({ position: { x: 80, y: 100 } });
  await dialog
    .getByLabel("Landmark / location note (optional)")
    .fill("Adjusted GPS pin");
  await page.screenshot({
    path: test.info().outputPath("mobile-location-picker.png"),
    fullPage: true,
  });
  await dialog
    .getByRole("button", { name: "Confirm location", exact: true })
    .click();
  await expect(page.locator(".location-field")).toContainText(
    "Adjusted GPS pin",
  );
  await expect(page.locator(".location-field")).not.toContainText(
    "7.770000, 125.010000",
  );
  // Double rendered text sizes to check wrapping independently of device pixel density.
  await page.evaluate(() => {
    const elements = [
      ...document.querySelectorAll<HTMLElement>(".shell, .shell *"),
    ];
    const sizes = elements.map(
      (element) => parseFloat(getComputedStyle(element).fontSize) * 2,
    );
    elements.forEach(
      (element, index) => (element.style.fontSize = `${sizes[index]}px`),
    );
  });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  await page
    .getByRole("button", { name: "Open navigation", exact: true })
    .click();
  await expect(
    page.getByRole("link", { name: "Service concerns", exact: true }),
  ).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
});

test("midnight dashboard uses verified activity and mobile dock respects role routes", async ({
  page,
  request,
}) => {
  await login(page, "client");
  await expect(page.locator(".consumer-balance")).toHaveCSS(
    "background-color",
    "rgb(8, 27, 61)",
  );
  await expect(
    page.getByRole("heading", { name: "Payment verified", exact: true }),
  ).toBeVisible();
  await page
    .getByRole("link", { name: "View transaction", exact: true })
    .click();
  await expect(page).toHaveURL(/payments\?billId=/);
  await expect(page.getByText("QA-RECEIPT-001")).toBeVisible();
  await request.post(`${fixture}/__test/scenario`, {
    data: { payments: [], notices: [] },
  });
  await page.goto("/portal");
  await expect(
    page.getByRole("heading", { name: "No recent transactions", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", { name: "Payment verified", exact: true }),
  ).toHaveCount(0);
  await expect(
    page.getByText("Live service status is not available.", { exact: false }),
  ).toBeVisible();
  await page.screenshot({
    path: test.info().outputPath("midnight-consumer-dashboard.png"),
    fullPage: true,
  });
  await page.setViewportSize({ width: 390, height: 844 });
  const dock = page.getByRole("navigation", {
    name: "Quick navigation",
    exact: true,
  });
  await expect(dock).toBeVisible();
  await dock.getByRole("link", { name: "Bills", exact: true }).click();
  await expect(page).toHaveURL(/portal\/bills$/);
  await expect(
    dock.getByRole("link", { name: "Bills", exact: true }),
  ).toHaveAttribute("aria-current", "page");
  await dock.getByRole("link", { name: "Requests", exact: true }).click();
  await expect(page).toHaveURL(/portal\/concerns$/);
  await page.screenshot({
    path: test.info().outputPath("midnight-mobile-navigation.png"),
    fullPage: true,
  });
  await page.setViewportSize({ width: 1280, height: 800 });
  await login(page, "staff");
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(
    dock.getByRole("link", { name: "Accounts", exact: true }),
  ).toHaveCount(0);
  await dock.getByRole("link", { name: "Repairs", exact: true }).click();
  await expect(page).toHaveURL(/office\/repairs$/);
});

test("landing Android downloads open release instructions with the signed APK link", async ({
  page,
}) => {
  await page.goto("/");
  await expect(page.locator("[data-download-apk]")).toHaveCount(2);
  await page.locator(".hero [data-download-apk]").click();
  await expect(page).toHaveURL(/\/download$/);
  await expect(
    page.getByRole("heading", { name: /Your water services/ }),
  ).toBeVisible();
  await expect(page.getByText("Version 1.0.1", { exact: false })).toBeVisible();
  const link = page.getByRole("link", { name: "Download APK", exact: true });
  await expect(link).toHaveAttribute(
    "href",
    "https://github.com/ishikawa321/Water_Disctrict/releases/download/android-v1.0.1/WaterDistrictConnect-1.0.1.apk",
  );
  await page.getByText("Release details and checksum", { exact: true }).click();
  await expect(
    page.getByText("ph.maramag.waterdistrictconnect", { exact: true }),
  ).toBeVisible();
  await expect(page.locator(".apk-checksum")).toHaveText(
    "637244eb7ee2871d78722025179c6c47193e81f4cbd2072bdba4d9110ab46303",
  );
  await page.setViewportSize({ width: 320, height: 720 });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await page.screenshot({
    path: test.info().outputPath("android-download-mobile.png"),
    fullPage: true,
  });
  await page.route(
    "https://github.com/ishikawa321/Water_Disctrict/releases/download/android-v1.0.1/WaterDistrictConnect-1.0.1.apk",
    (route) =>
      route.fulfill({
        contentType: "application/vnd.android.package-archive",
        headers: {
          "content-disposition":
            "attachment; filename=WaterDistrictConnect-1.0.1.apk",
        },
        body: "isolated browser download fixture",
      }),
  );
  const downloaded = page.waitForEvent("download");
  await link.click();
  expect((await downloaded).suggestedFilename()).toBe(
    "WaterDistrictConnect-1.0.1.apk",
  );
  await page
    .getByRole("link", { name: "Back to the website", exact: true })
    .click();
  await expect(page).toHaveURL(/:3100\/$/);
  await page.locator("#explore [data-download-apk]").click();
  await expect(page).toHaveURL(/\/download$/);
  await page.getByRole("link", { name: "Open web app", exact: false }).click();
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.locator(".feedback.error")).toHaveCount(0);
});

test("saved repairs load without the desktop server or workflow setup, and Staff cannot review a dispatched concern", async ({
  page,
  request,
}) => {
  const state = await (await request.get(`${fixture}/__test/state`)).json();
  const ticketId = "50000000-0000-4000-8000-000000000001";
  state.concerns[0].ticketId = ticketId;
  state.concerns[0].status = "Under review";
  await request.post(`${fixture}/__test/scenario`, {
    data: {
      workflowAvailable: false,
      concerns: state.concerns,
      tickets: [
        {
          id: ticketId,
          concernId: state.concerns[0].id,
          accountNumber: "QA-001",
          subject: "QA low pressure",
          status: "Open",
          assignedTo: null,
          assignedToUserId: null,
          latestUpdate: "Saved inspection request",
          updatedAt: "2026-11-26T08:00:00Z",
          version: 2,
          history: [
            {
              id: 1,
              status: "Open",
              note: "Saved inspection request",
              changedBy: "QA Admin",
              assignedTo: null,
              changedAt: "2026-11-26T08:00:00Z",
            },
          ],
        },
      ],
    },
  });
  await login(page, "admin");
  await page.getByRole("link", { name: "Repair tickets", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Saved repair tickets" }),
  ).toBeVisible();
  await page
    .getByRole("textbox", { name: "Search subject or account" })
    .fill("QA-001");
  await page
    .getByRole("button", { name: "Apply filters", exact: true })
    .click();
  await page.getByRole("button", { name: /QA low pressure/ }).click();
  await expect(page.locator(".timeline li")).toHaveCount(1);
  await expect(
    page.getByText("The office service is not connected yet", { exact: false }),
  ).toHaveCount(0);
  await page.screenshot({
    path: test.info().outputPath("independent-office-repairs.png"),
    fullPage: true,
  });
  await login(page, "staff");
  await page
    .getByRole("link", { name: "Service concerns", exact: true })
    .click();
  await page.getByRole("button", { name: /QA low pressure/ }).click();
  await expect(
    page.getByText("Only its assigned Staff and Admin", { exact: false }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Save review", exact: true }),
  ).toHaveCount(0);
});
