using System.Text.Json;
using Npgsql;
namespace WaterDistrict.Tests;

[Collection("Postgres")]
public sealed class StaffRoleTests
{
    private static CancellationToken Token => TestContext.Current.CancellationToken;
    private static Task<JsonElement> As(PostgresDatabase db, Guid user, string sql) => WebOfficeWorkflowTests.AsCaller(db, user, sql);
    private static async Task Install(PostgresDatabase db)
    {
        await db.SqlAsync("alter table auth.users add column if not exists email text,add column if not exists email_confirmed_at timestamptz,add column if not exists raw_user_meta_data jsonb default '{}'");
        await WebOfficeWorkflowTests.Install(db);
        await db.SqlAsync(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "billing-automation.sql"), Token));
        var sql = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "staff-role.sql"), Token); await db.SqlAsync(sql); await db.SqlAsync(sql);
    }
    private static async Task<JsonElement> Raw(PostgresDatabase db, string sql) { await using var c = new NpgsqlConnection(db.Connection); await c.OpenAsync(Token); await using var cmd = new NpgsqlCommand(sql, c); return JsonDocument.Parse((string)(await cmd.ExecuteScalarAsync(Token))!).RootElement.Clone(); }
    [Fact]
    public async Task Staff_can_read_bills_and_confirm_payments_but_cannot_edit_plans_or_issue_bills()
    {
        await using var db = await PostgresDatabase.CreateAsync(verifiedSchema: true); await Install(db);
        var bill = await As(db, db.Admin.UserId, $"select public.wd_billing_create_bill('{Guid.NewGuid()}','{db.AccountId}',300,current_date+3)::text"); var id = bill.GetProperty("id").GetGuid();
        var list = await As(db, db.Staff.UserId, "select jsonb_build_object('count',count(*))::text from public.bills"); Assert.Equal(1, list.GetProperty("count").GetInt32());
        var payment = await As(db, db.Staff.UserId, $"select public.wd_billing_confirm_payment('{Guid.NewGuid()}','{id}',100,(clock_timestamp() at time zone 'Asia/Manila')::date)::text"); Assert.Equal(db.Staff.UserId, payment.GetProperty("verified_by").GetGuid()); Assert.Matches("^[0-9]{10}$", payment.GetProperty("receipt_reference").GetString()!);
        await As(db, db.Staff.UserId, "select public.wd_billing_refresh()::text");
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Staff.UserId, $"select public.wd_billing_set_plan('{db.AccountId}',200,true)::text"))).SqlState);
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Staff.UserId, $"select public.wd_billing_create_bill('{Guid.NewGuid()}','{db.AccountId}',200,current_date+3)::text"))).SqlState);
        var client = await As(db, db.OtherClientId, "select jsonb_build_object('count',count(*))::text from public.bills"); Assert.Equal(0, client.GetProperty("count").GetInt32());
    }
    [Fact]
    public async Task Completion_does_not_resolve_concern_until_admin_confirms_and_other_staff_cannot_read()
    {
        await using var db = await PostgresDatabase.CreateAsync(verifiedSchema: true); await Install(db); var concern = Guid.NewGuid();
        await As(db, db.Staff.UserId, $"select public.wd_web_workflow('intake','{concern}',null,'{{\"accountId\":\"{db.AccountId}\",\"category\":\"Repair request\",\"subject\":\"Test\",\"description\":\"Repair\"}}')::text");
        async Task<long> Version(string table, Guid id) => (await Raw(db, $"select jsonb_build_object('v',xmin::text::bigint)::text from public.{table} where id='{id}'")).GetProperty("v").GetInt64();
        await As(db, db.Staff.UserId, $"select public.wd_web_workflow('review','{concern}',{await Version("service_concerns", concern)},'{{\"status\":\"Under review\"}}')::text");
        var ticket = await As(db, db.Admin.UserId, $"select public.wd_web_workflow('dispatch','{concern}',{await Version("service_concerns", concern)},'{{\"note\":\"Dispatch\"}}')::text"); var id = ticket.GetProperty("id").GetGuid();
        async Task Change(Guid actor, string status) => await As(db, actor, $"select public.wd_web_workflow('update_ticket','{id}',{await Version("repair_tickets", id)},'{{\"status\":\"{status}\",\"note\":\"Saved {status}\",\"assignedToUserId\":\"{db.Staff.UserId}\"}}')::text");
        await Change(db.Admin.UserId, "Assigned"); await Change(db.Staff.UserId, "In progress");
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => Change(db.Staff.UserId, "Resolved"))).SqlState);
        await Change(db.Staff.UserId, "Completed");
        var c = await Raw(db, $"select jsonb_build_object('status',status)::text from public.service_concerns where id='{concern}'"); Assert.Equal("Under review", c.GetProperty("status").GetString());
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => Change(db.Staff.UserId, "Resolved"))).SqlState);
        var other = Guid.NewGuid(); await db.SqlAsync($"insert into auth.users(id) values('{other}');insert into public.profiles(user_id,display_name,role,active) values('{other}','Other Staff','staff',true)");
        Assert.Equal(0, (await As(db, other, $"select jsonb_build_object('count',count(*))::text from public.repair_tickets where id='{id}'")).GetProperty("count").GetInt32());
        await Change(db.Admin.UserId, "Resolved"); Assert.Equal("Resolved", (await Raw(db, $"select jsonb_build_object('status',status)::text from public.service_concerns where id='{concern}'")).GetProperty("status").GetString());
        Assert.Equal(5, (await As(db, db.Staff.UserId, $"select public.wd_web_ticket_history('{id}')::text")).GetArrayLength());
    }
    [Theory]
    [InlineData("Assigned", false)]
    [InlineData("In progress", false)]
    [InlineData("Completed", false)]
    [InlineData("Assigned", true)]
    [InlineData("In progress", true)]
    [InlineData("Completed", true)]
    public async Task Direct_resolution_updates_concern_and_history(string from, bool admin)
    {
        await using var db = await PostgresDatabase.CreateAsync(verifiedSchema: true); await Install(db);
        var migration = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "allow_staff_repair_resolution.sql"), Token);
        await db.SqlAsync(migration); await db.SqlAsync(migration);
        var concern = Guid.NewGuid();
        await As(db, db.Staff.UserId, $"select public.wd_web_workflow('intake','{concern}',null,'{{\"accountId\":\"{db.AccountId}\",\"category\":\"Repair request\",\"subject\":\"Direct resolution\",\"description\":\"Repair\"}}')::text");
        async Task<long> Version(string table, Guid key) => (await Raw(db, $"select jsonb_build_object('v',xmin::text::bigint)::text from public.{table} where id='{key}'")).GetProperty("v").GetInt64();
        await As(db, db.Staff.UserId, $"select public.wd_web_workflow('review','{concern}',{await Version("service_concerns", concern)},'{{\"status\":\"Under review\"}}')::text");
        var ticket = await As(db, db.Admin.UserId, $"select public.wd_web_workflow('dispatch','{concern}',{await Version("service_concerns", concern)},'{{\"note\":\"Dispatch\"}}')::text"); var id = ticket.GetProperty("id").GetGuid();
        async Task Change(Guid actor, string status, string note = "Saved update") => await As(db, actor, $"select public.wd_web_workflow('update_ticket','{id}',{await Version("repair_tickets", id)},'{{\"status\":\"{status}\",\"note\":\"{note}\",\"assignedToUserId\":\"{db.Staff.UserId}\"}}')::text");
        await Change(db.Admin.UserId, "Assigned");
        if (from != "Assigned") await Change(db.Staff.UserId, "In progress");
        if (from == "Completed") await Change(db.Staff.UserId, "Completed");
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => Change(db.OtherClientId, "Resolved"))).SqlState);
        var other = Guid.NewGuid(); await db.SqlAsync($"insert into auth.users(id) values('{other}');insert into public.profiles(user_id,display_name,role,active) values('{other}','Other Staff','staff',true)");
        await Assert.ThrowsAsync<PostgresException>(() => Change(other, "Resolved"));
        var actor = admin ? db.Admin.UserId : db.Staff.UserId;
        await Assert.ThrowsAsync<PostgresException>(() => Change(actor, "Resolved", ""));
        await Change(actor, "Resolved");
        Assert.Equal("Resolved", (await Raw(db, $"select jsonb_build_object('status',status)::text from public.service_concerns where id='{concern}'")).GetProperty("status").GetString());
        var history = await As(db, db.Staff.UserId, $"select public.wd_web_ticket_history('{id}')::text");
        Assert.Contains(history.EnumerateArray(), e => e.GetProperty("status").GetString() == "Resolved" && e.GetProperty("changedBy").GetString() == (admin ? "Admin test" : "Staff test"));
        await Assert.ThrowsAsync<PostgresException>(() => Change(actor, "In progress"));
    }
    [Fact]
    public async Task Only_admin_invites_and_email_confirmation_activates_invited_staff_without_customer_link()
    {
        await using var db = await PostgresDatabase.CreateAsync(verifiedSchema: true); await Install(db);
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Staff.UserId, "select public.wd_staff_invite('field@example.test','Field Staff')::text"))).SqlState);
        var invite = await As(db, db.Admin.UserId, "select public.wd_staff_invite('field@example.test','Field Staff')::text"); var token = invite.GetProperty("token").GetString(); var id = Guid.NewGuid();
        await db.SqlAsync($"insert into auth.users(id,email,raw_user_meta_data) values('{id}','field@example.test','{{\"registration_source\":\"staff_invite_v1\",\"staff_invite_token\":\"{token}\",\"role\":\"admin\"}}')");
        var pending = await Raw(db, $"select to_jsonb(p)::text from public.profiles p where user_id='{id}'"); Assert.Equal("staff", pending.GetProperty("role").GetString()); Assert.False(pending.GetProperty("active").GetBoolean());
        await db.SqlAsync($"update auth.users set email_confirmed_at=now() where id='{id}'"); Assert.True((await Raw(db, $"select to_jsonb(p)::text from public.profiles p where user_id='{id}'")).GetProperty("active").GetBoolean());
        await Assert.ThrowsAsync<PostgresException>(() => db.SqlAsync($"insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values('{Guid.NewGuid()}','field@example.test',now(),'{{\"registration_source\":\"staff_invite_v1\",\"staff_invite_token\":\"{token}\"}}')"));
        Assert.Equal(0, (await As(db, id, "select jsonb_build_object('count',count(*))::text from public.account_access")).GetProperty("count").GetInt32());
        await As(db, db.Admin.UserId, $"select public.wd_staff_access('{id}',false)::text");
        await db.SqlAsync($"update auth.users set email_confirmed_at=now() where id='{id}'"); Assert.False((await Raw(db, $"select to_jsonb(p)::text from public.profiles p where user_id='{id}'")).GetProperty("active").GetBoolean());
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => As(db, id, "select public.wd_billing_refresh()::text"))).SqlState);
        Assert.Equal("22023", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Admin.UserId, "select public.wd_staff_invite('field@example.test','Again')::text"))).SqlState);
    }
    [Fact]
    public async Task Forged_wrong_email_expired_revoked_and_reused_invitations_never_grant_staff()
    {
        await using var db = await PostgresDatabase.CreateAsync(verifiedSchema: true); await Install(db);
        var invite = await As(db, db.Admin.UserId, "select public.wd_staff_invite('staff@example.test','Staff')::text"); var token = invite.GetProperty("token").GetString(); var invitation = invite.GetProperty("id").GetGuid();
        async Task Signup(string email, string t) => await db.SqlAsync($"insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values('{Guid.NewGuid()}','{email}',now(),'{{\"registration_source\":\"staff_invite_v1\",\"staff_invite_token\":\"{t}\"}}')");
        await Assert.ThrowsAsync<PostgresException>(() => Signup("wrong@example.test", token!)); await Assert.ThrowsAsync<PostgresException>(() => Signup("staff@example.test", Guid.NewGuid().ToString()));
        await db.SqlAsync($"update public.staff_invitations set expires_at=now()-interval '1 day' where id='{invitation}'");
        await Assert.ThrowsAsync<PostgresException>(() => Signup("staff@example.test", token!));
        await db.SqlAsync($"update public.staff_invitations set expires_at=now()+interval '1 day' where id='{invitation}'");
        await As(db, db.Admin.UserId, $"select public.wd_staff_revoke_invite('{invitation}')::text"); await Assert.ThrowsAsync<PostgresException>(() => Signup("staff@example.test", token!));
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.ClientId, "select public.wd_staff_directory()::text"))).SqlState);
    }
}
