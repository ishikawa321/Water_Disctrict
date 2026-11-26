using System.Diagnostics;
using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.IdentityModel.Tokens;
using Npgsql;

namespace WaterDistrict.Tests;

[Collection("Postgres")]
public sealed class WebPostgrestTests
{
    private static CancellationToken Token => TestContext.Current.CancellationToken;
    [Fact(Timeout = 60000)]
    public async Task Real_data_api_exposes_xmin_relations_counts_and_atomic_rpcs_under_caller_rls()
    {
        var executable = Environment.GetEnvironmentVariable("WATERDISTRICT_TEST_POSTGREST");
        Assert.SkipWhen(string.IsNullOrWhiteSpace(executable) || !File.Exists(executable), "Set WATERDISTRICT_TEST_POSTGREST to an official local PostgREST executable.");
        await using var database = await PostgresDatabase.CreateAsync(verifiedSchema: true); await WebOfficeWorkflowTests.Install(database);
        await database.SqlAsync("alter table auth.users add column email text,add column email_confirmed_at timestamptz,add column raw_user_meta_data jsonb default '{}'");
        await database.SqlAsync(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "billing-automation.sql"), Token));
        await database.SqlAsync(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "staff-role.sql"), Token));
        var connection = new NpgsqlConnectionStringBuilder(database.Connection);
        const string secret = "isolated-local-postgrest-qa-signing-key-only";
        var start = new ProcessStartInfo(executable!) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        start.Environment["PGRST_DB_URI"] = $"postgresql://{connection.Username}@127.0.0.1:55439/{connection.Database}";
        start.Environment["PGRST_DB_SCHEMAS"] = "public"; start.Environment["PGRST_DB_ANON_ROLE"] = "anon";
        start.Environment["PGRST_JWT_SECRET"] = secret; start.Environment["PGRST_SERVER_HOST"] = "127.0.0.1"; start.Environment["PGRST_SERVER_PORT"] = "54340"; start.Environment["PGRST_LOG_LEVEL"] = "crit";
        using var process = Process.Start(start)!; var output = process.StandardOutput.ReadToEndAsync(Token); var errors = process.StandardError.ReadToEndAsync(Token);
        using var client = new HttpClient { BaseAddress = new Uri("http://127.0.0.1:54340"), Timeout = TimeSpan.FromSeconds(2) };
        try
        {
            var ready = false;
            for (var attempt = 0; attempt < 20 && !ready; attempt++) { Assert.False(process.HasExited, "PostgREST exited before startup. On Windows, put PostgreSQL's bin directory (libpq) on PATH."); try { ready = (await client.GetAsync("/", Token)).IsSuccessStatusCode; } catch (HttpRequestException) { } if (!ready) await Task.Delay(250, Token); }
            Assert.True(ready, "Local PostgREST did not start.");
            void Login(Guid user)
            {
                var token = new JwtSecurityToken(claims: [new Claim("sub", user.ToString()), new Claim("role", "authenticated")], expires: DateTime.UtcNow.AddMinutes(10), signingCredentials: new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret)), SecurityAlgorithms.HmacSha256));
                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token));
            }
            async Task<JsonElement> Get(string path)
            { using var response = await client.GetAsync(path, Token); var text = await response.Content.ReadAsStringAsync(Token); Assert.True(response.IsSuccessStatusCode, text); return JsonDocument.Parse(text).RootElement.Clone(); }
            async Task<JsonElement> Rpc(string action, Guid id, long? version, object payload)
            { using var response = await client.PostAsJsonAsync("/rpc/wd_web_workflow", new { p_action = action, p_id = id, p_version = version, p_payload = payload }, Token); var text = await response.Content.ReadAsStringAsync(Token); Assert.True(response.IsSuccessStatusCode, text); return JsonDocument.Parse(text).RootElement.Clone(); }
            static long Version(JsonElement value) => long.Parse(value.GetProperty("xmin").ToString());
            Login(database.Admin.UserId);
            var concernId = Guid.NewGuid();
            await Rpc("intake", concernId, null, new { accountId = database.AccountId, category = "Repair request", subject = "HTTP report", description = "Verified through real PostgREST", latitude = 7.76, longitude = 125, locationNote = "Near HTTP test meter" });
            var records = await Get("/service_concerns?select=id,xmin,latitude,longitude,location_note,service_accounts(account_number),repair_tickets(id)");
            Assert.Single(records.EnumerateArray()); var initial = Version(records[0]); Assert.True(initial > 0); Assert.Equal("TEST-001", records[0].GetProperty("service_accounts").GetProperty("account_number").GetString());
            using (var request = new HttpRequestMessage(HttpMethod.Head, "/service_concerns?select=id&status=in.(Submitted,Under%20review)"))
            { request.Headers.Add("Prefer", "count=exact"); using var result = await client.SendAsync(request, Token); Assert.True(result.IsSuccessStatusCode, $"{result.StatusCode}: {result.Headers} {result.Content.Headers}"); Assert.Equal("0-0/1", Assert.Single(result.Content.Headers.GetValues("Content-Range"))); }
            await Rpc("review", concernId, initial, new { status = "Under review", response = "HTTP review" });
            records = await Get("/service_concerns?select=id,xmin"); var reviewed = Version(records[0]); Assert.NotEqual(initial, reviewed);
            var dispatched = await Rpc("dispatch", concernId, reviewed, new { note = "HTTP approved dispatch" }); var ticketId = dispatched.GetProperty("id").GetGuid();
            var tickets = await Get("/repair_tickets?select=id,xmin,status,assigned_to_user_id,service_concerns!inner(account_id,subject,service_accounts(account_number))");
            Assert.Single(tickets.EnumerateArray()); Assert.Equal("HTTP report", tickets[0].GetProperty("service_concerns").GetProperty("subject").GetString());
            var ticketVersion = Version(tickets[0]); Login(database.Staff.UserId);
            // Inner relationships must filter parent tickets for account-number search.
            Login(database.Admin.UserId);
            Assert.Single((await Get("/repair_tickets?select=id,service_concerns!inner(service_accounts!inner(account_number))&service_concerns.service_accounts.account_number=ilike.*TEST-001*")).EnumerateArray());
            Assert.Empty((await Get("/repair_tickets?select=id,service_concerns!inner(service_accounts!inner(account_number))&service_concerns.service_accounts.account_number=ilike.*NO-MATCH*")).EnumerateArray());
            Login(database.Staff.UserId);
            Assert.Empty((await Get("/repair_tickets?select=id,xmin")).EnumerateArray());
            Login(database.Admin.UserId); await Rpc("update_ticket", ticketId, ticketVersion, new { status = "Assigned", assignedToUserId = database.Staff.UserId, note = "HTTP assignment" });
            Login(database.Staff.UserId); tickets = await Get("/repair_tickets?select=id,xmin,status,assigned_to_user_id"); Assert.Single(tickets.EnumerateArray());
            await Rpc("update_ticket", ticketId, Version(tickets[0]), new { status = "In progress", assignedToUserId = database.Staff.UserId, note = "HTTP work started" });
            using (var history = await client.PostAsJsonAsync("/rpc/wd_web_ticket_history", new { p_ticket_id = ticketId }, Token))
            { history.EnsureSuccessStatusCode(); var events = await history.Content.ReadFromJsonAsync<JsonElement>(Token); Assert.Equal(3, events.GetArrayLength()); Assert.Equal(database.Admin.DisplayName, events[0].GetProperty("changedBy").GetString()); }
            tickets = await Get("/repair_tickets?select=id,xmin");
            await Rpc("update_ticket", ticketId, Version(tickets[0]), new { status = "Completed", assignedToUserId = database.Staff.UserId, note = "Work finished, awaiting approval" });
            tickets = await Get("/repair_tickets?select=id,xmin");
            using (var forbidden = await client.PostAsJsonAsync("/rpc/wd_web_workflow", new { p_action = "update_ticket", p_id = ticketId, p_version = Version(tickets[0]), p_payload = new { status = "Resolved", assignedToUserId = database.Staff.UserId, note = "Forbidden Staff approval" } }, Token)) Assert.Equal(HttpStatusCode.Forbidden, forbidden.StatusCode);
            Login(database.Admin.UserId);
            await Rpc("update_ticket", ticketId, Version(tickets[0]), new { status = "Resolved", assignedToUserId = database.Staff.UserId, note = "Admin confirmed" });
            using (var invite = await client.PostAsJsonAsync("/rpc/wd_staff_invite", new { p_email = "http-staff@example.test", p_display_name = "HTTP Staff" }, Token))
            {
                Assert.True(invite.IsSuccessStatusCode, await invite.Content.ReadAsStringAsync(Token)); var i = await invite.Content.ReadFromJsonAsync<JsonElement>(Token); client.DefaultRequestHeaders.Authorization = null;
                using var preview = await client.PostAsJsonAsync("/rpc/wd_staff_invitation", new { p_token = i.GetProperty("token").GetString() }, Token); Assert.True(preview.IsSuccessStatusCode, await preview.Content.ReadAsStringAsync(Token));
            }
            Login(database.OtherClientId); Assert.Empty((await Get("/repair_tickets?select=id")).EnumerateArray());
            using var denied = await client.PostAsJsonAsync("/rpc/wd_web_workflow", new { p_action = "dispatch", p_id = concernId, p_version = reviewed, p_payload = new { note = "Forbidden" } }, Token); Assert.Equal(HttpStatusCode.Forbidden, denied.StatusCode);
        }
        finally
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            await process.WaitForExitAsync(Token); await Task.WhenAll(output, errors);
        }
    }
}
