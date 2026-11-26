using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using NpgsqlTypes;
using WaterDistrict.Application;
using WaterDistrict.Infrastructure;

namespace WaterDistrict.Tests;

[Collection("Postgres")]
public sealed class WebOfficeWorkflowTests
{
    private static CancellationToken Token => TestContext.Current.CancellationToken;
    internal static async Task Install(PostgresDatabase database)
    {
        var sql = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "web-office-workflows.sql"), Token);
        await database.SqlAsync(sql);
        await database.SqlAsync(sql);
    }
    internal static async Task<JsonElement> AsCaller(PostgresDatabase database, Guid user, string sql, params NpgsqlParameter[] parameters)
    {
        await using var connection = new NpgsqlConnection(database.Connection); await connection.OpenAsync(Token);
        await using var tx = await connection.BeginTransactionAsync(Token);
        await using (var identity = new NpgsqlCommand($"SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','{user}',true)", connection, tx)) await identity.ExecuteNonQueryAsync(Token);
        await using var command = new NpgsqlCommand(sql, connection, tx); command.Parameters.AddRange(parameters);
        var result = (string)(await command.ExecuteScalarAsync(Token))!; await tx.CommitAsync(Token);
        return JsonDocument.Parse(result).RootElement.Clone();
    }
    private static Task<JsonElement> Call(PostgresDatabase db, Guid user, string action, Guid id, uint? version, object payload) =>
        AsCaller(db, user, "select public.wd_web_workflow(@action,@id,@version,@payload)::text",
            new("action", action), new("id", id), new("version", NpgsqlDbType.Bigint) { Value = version is uint v ? (object)(long)v : DBNull.Value }, new("payload", NpgsqlDbType.Jsonb) { Value = JsonSerializer.Serialize(payload) });
    private static async Task<ConcernRecord> ReadConcern(PostgresDatabase database, Guid id)
    { await using var db = database.Open(); return await new WorkflowService(db).ConcernAsync(database.Admin, id, Token); }

    [Fact]
    public async Task Rls_web_intake_review_dispatch_assignment_and_resolution_keep_original_atomic_history()
    {
        await using var database = await PostgresDatabase.CreateAsync(verifiedSchema: true); await Install(database);
        var id = Guid.NewGuid(); var input = new { accountId = database.AccountId, category = "Repair request", subject = "Web report", description = "Test shared service report.", latitude = 7.7633, longitude = 125.0058, locationNote = " Near meter " };
        await Call(database, database.Staff.UserId, "intake", id, null, input);
        await Call(database, database.Staff.UserId, "intake", id, null, input);
        var initial = await ReadConcern(database, id); Assert.Equal("Near meter", initial.LocationNote);
        Assert.Equal("40001", (await Assert.ThrowsAsync<PostgresException>(() => Call(database, database.Admin.UserId, "intake", id, null, input))).SqlState);
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => Call(database, database.ClientId, "review", id, initial.Version, new { status = "Closed", response = "Denied" }))).SqlState);
        await Call(database, database.Staff.UserId, "review", id, initial.Version, new { status = "Under review", response = "Checked the reported location." });
        var reviewed = await ReadConcern(database, id);
        Assert.Equal("40001", (await Assert.ThrowsAsync<PostgresException>(() => Call(database, database.Admin.UserId, "dispatch", id, initial.Version, new { note = "Stale version" }))).SqlState);
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => Call(database, database.Staff.UserId, "dispatch", id, reviewed.Version, new { note = "Forbidden dispatch" }))).SqlState);
        var opened = await Call(database, database.Admin.UserId, "dispatch", id, reviewed.Version, new { note = "Approved shared repair." }); var ticketId = opened.GetProperty("id").GetGuid();
        await using var context = database.Open(); var service = new WorkflowService(context);
        var detail = await service.TicketAsync(database.Admin, ticketId, Token); Assert.Single(detail.History);
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => AsCaller(database, database.Staff.UserId, $"select public.wd_web_ticket_history('{ticketId}')::text"))).SqlState);
        Assert.Equal("23514", (await Assert.ThrowsAsync<PostgresException>(() => Call(database, database.Admin.UserId, "update_ticket", ticketId, detail.Ticket.Version, new { status = "Assigned", assignedToUserId = database.ClientId, note = "Not staff" }))).SqlState);
        await Call(database, database.Admin.UserId, "update_ticket", ticketId, detail.Ticket.Version, new { status = "Assigned", assignedToUserId = database.Staff.UserId, note = "Assigned qualified staff." });
        detail = await service.TicketAsync(database.Admin, ticketId, Token);
        Assert.Equal("40001", (await Assert.ThrowsAsync<PostgresException>(() => Call(database, database.Staff.UserId, "update_ticket", ticketId, detail.Ticket.Version - 1, new { status = "In progress", assignedToUserId = database.Staff.UserId, note = "Stale write" }))).SqlState);
        foreach (var state in new[] { "In progress", "Resolved" })
        { await Call(database, database.Staff.UserId, "update_ticket", ticketId, detail.Ticket.Version, new { status = state, assignedToUserId = database.Staff.UserId, note = "Verified update " + state }); detail = await service.TicketAsync(database.Admin, ticketId, Token); }
        Assert.Equal(4, detail.History.Count); Assert.Equal("Resolved", (await ReadConcern(database, id)).Status);
        var history = await AsCaller(database, database.Staff.UserId, $"select public.wd_web_ticket_history('{ticketId}')::text");
        Assert.Equal(database.Admin.DisplayName, history[0].GetProperty("changedBy").GetString());
        Assert.Equal(4, history.GetArrayLength());
        var other = await AsCaller(database, database.OtherClientId, "select jsonb_build_object('count',count(*))::text from public.repair_tickets"); Assert.Equal(0, other.GetProperty("count").GetInt32());
    }

    [Fact]
    public async Task Concurrent_dispatch_is_single_and_essential_failure_rolls_back_all_records()
    {
        await using var database = await PostgresDatabase.CreateAsync(verifiedSchema: true); await Install(database);
        var id = Guid.NewGuid(); await Call(database, database.Admin.UserId, "intake", id, null, new { accountId = database.AccountId, category = "Repair request", subject = "Concurrent report", description = "Test report" });
        var c = await ReadConcern(database, id); await Call(database, database.Admin.UserId, "review", id, c.Version, new { status = "Under review", response = "Reviewed" }); c = await ReadConcern(database, id);
        async Task<bool> Attempt() { try { await Call(database, database.Admin.UserId, "dispatch", id, c.Version, new { note = "Approved" }); return true; } catch (PostgresException e) { Assert.Contains(e.SqlState, new[] { "40001", "23505" }); return false; } }
        var results = await Task.WhenAll(Attempt(), Attempt()); Assert.Single(results, r => r);
        await using (var context = database.Open()) { Assert.Equal(1, await context.Tickets.CountAsync(Token)); Assert.Equal(1, await context.History.CountAsync(Token)); }
        var second = Guid.NewGuid(); await Call(database, database.Admin.UserId, "intake", second, null, new { accountId = database.AccountId, category = "Repair request", subject = "Rollback report", description = "Test rollback" });
        var pending = await ReadConcern(database, second); await Call(database, database.Admin.UserId, "review", second, pending.Version, new { status = "Under review", response = "Reviewed" }); pending = await ReadConcern(database, second);
        await database.SqlAsync($"CREATE FUNCTION public.web_test_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.id='{second}'::uuid AND NEW.repair_dispatched_at IS NOT NULL THEN RAISE EXCEPTION 'Controlled test failure'; END IF; RETURN NEW; END $$; CREATE TRIGGER web_test_fail BEFORE UPDATE ON public.service_concerns FOR EACH ROW EXECUTE FUNCTION public.web_test_fail();");
        await Assert.ThrowsAsync<PostgresException>(() => Call(database, database.Admin.UserId, "dispatch", second, pending.Version, new { note = "Must roll back" }));
        await using var fresh = database.Open(); Assert.Equal(1, await fresh.Tickets.CountAsync(Token)); Assert.Equal(1, await fresh.History.CountAsync(Token)); Assert.Null((await ReadConcern(database, second)).TicketId);
    }
}
