using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Npgsql;
using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;
using WaterDistrictConnect.Core.Persistence;

namespace WaterDistrictConnect.IntegrationTests;
public sealed class PostgreSqlFactAttribute : FactAttribute
{
    public PostgreSqlFactAttribute()
    {
        if (Environment.GetEnvironmentVariable("MWD_ALLOW_DISPOSABLE_DATABASE_DROP") != "true") Skip = "Legacy later-phase tests require explicit operator opt-in to disposable database creation/deletion. Phase 1 uses retained test databases instead.";
        else if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("MWD_TEST_ADMIN"))) Skip = "Set MWD_TEST_ADMIN to a dedicated PostgreSQL test server connection. No database substitute is used.";
    }
}
public sealed class TestFactory(string connection, SaveChangesInterceptor? interceptor = null) : IDbContextFactory<WaterDbContext>
{
    public WaterDbContext CreateDbContext() { var b = new DbContextOptionsBuilder<WaterDbContext>().UseNpgsql(connection); if (interceptor != null) b.AddInterceptors(interceptor); return new(b.Options); }
}
public sealed class FailHistoryWrite : SaveChangesInterceptor
{
    public bool Armed { get; set; }
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        if (Armed && eventData.Context!.ChangeTracker.Entries<TicketEvent>().Any(x => x.State == EntityState.Added)) throw new InvalidOperationException("Injected essential history write failure");
        return ValueTask.FromResult(result);
    }
}
public sealed class PostgreSqlTests : IAsyncLifetime
{
    private string admin = "", database = ""; private TestFactory factory = null!; private readonly Session session = new(); private AuthenticationService auth = null!; private WaterService service = null!;
    public async Task InitializeAsync()
    {
        admin = Environment.GetEnvironmentVariable("MWD_TEST_ADMIN") ?? ""; if (admin == "") return;
        database = "mwd_test_" + Guid.NewGuid().ToString("N");
        await using var con = new NpgsqlConnection(admin); await con.OpenAsync(); await using var command = new NpgsqlCommand($"CREATE DATABASE \"{database}\"", con); await command.ExecuteNonQueryAsync();
        factory = new TestFactory(new NpgsqlConnectionStringBuilder(admin) { Database = database }.ConnectionString);
        await using var db = factory.CreateDbContext(); await db.Database.MigrateAsync(); await DemoSeeder.SeedAsync(db);
        auth = new(factory, session); service = new(factory, session);
    }
    public async Task DisposeAsync()
    {
        if (database == "") return;
        Assert.StartsWith("mwd_test_", database); NpgsqlConnection.ClearAllPools();
        await using var con = new NpgsqlConnection(admin); await con.OpenAsync(); await using var command = new NpgsqlCommand($"DROP DATABASE \"{database}\" WITH (FORCE)", con); await command.ExecuteNonQueryAsync();
    }
    private Task Login(string name) => auth.LoginAsync(name, DemoSeeder.Password);
    private Task<Guid> Submit(ConcernCategory category = ConcernCategory.OtherTechnicalConcern) => service.SubmitAsync(new(null, category, "Fictional leak report", "Water visible near fictional service point.", "12 Sample River Street", "", "ignored"));
    private async Task<Guid> Ticket()
    {
        await Login("amara"); var c = await Submit(); await Login("admin"); var detail = await service.ConcernAsync(c); return await service.CreateTicketAsync(c, detail.Row.Version);
    }
    private async Task Update(Guid id, TicketAction action, string text, Guid? plumber = null, bool internalNote = false)
    { var t = await service.TicketAsync(id); await service.UpdateTicketAsync(id, t.Row.Version, action, text, plumber, internalNote); }
    [PostgreSqlFact] public async Task SubmissionPersistsReceiptAndRejectsInvalidInput()
    {
        await Login("amara"); var c = await Submit(); var detail = await service.ConcernAsync(c);
        Assert.Equal(ConcernState.Submitted, detail.Row.State); Assert.Null(detail.FirstResponse); Assert.Single(detail.Timeline); Assert.Equal("Receipt", detail.Timeline[0].Kind);
        await Assert.ThrowsAsync<BusinessException>(() => service.SubmitAsync(new(null, ConcernCategory.OtherTechnicalConcern, "", "description", "location", "", "")));
        await using var fresh = factory.CreateDbContext(); Assert.Equal(1, await fresh.Concerns.CountAsync()); Assert.Equal(1, await fresh.ConcernEvents.CountAsync());
        var newSession = new Session(); var newAuth = new AuthenticationService(factory, newSession); await newAuth.LoginAsync("amara", DemoSeeder.Password); Assert.Equal(c, (await new WaterService(factory, newSession).ConcernsAsync()).Items.Single().Id);
    }
    [PostgreSqlFact] public async Task ConnectedWorkflowPreservesHumanResponseAssignmentCompletionAndHistory()
    {
        await Login("amara"); var c = await Submit(); await Login("handler"); var d = await service.ConcernAsync(c);
        await service.RespondAsync(c, d.Row.Version, "We reviewed your report. Next action: technical assessment.", false, ConcernCategory.OtherTechnicalConcern, false);
        var first = (await service.ConcernAsync(c)).FirstResponse; d = await service.ConcernAsync(c);
        await service.RespondAsync(c, d.Row.Version, "Second office response", false, ConcernCategory.OtherTechnicalConcern, false); Assert.Equal(first, (await service.ConcernAsync(c)).FirstResponse);
        await Login("coordinator"); d = await service.ConcernAsync(c); var id = await service.CreateTicketAsync(c, d.Row.Version);
        var plumbers = (await service.PlumbersAsync()).Where(x => x.Available).ToArray(); await Update(id, TicketAction.Assign, "Initial assignment", plumbers[0].Id); var firstAssignment = (await service.TicketAsync(id)).FirstAssigned;
        await Update(id, TicketAction.Assign, "Handover to another available resource", plumbers[1].Id); Assert.Equal(firstAssignment, (await service.TicketAsync(id)).FirstAssigned);
        await Update(id, TicketAction.Start, "Work started by office report"); await Update(id, TicketAction.Progress, "Private scheduling note", internalNote: true); await Update(id, TicketAction.Resolve, "Fictional connection repaired and checked"); await Update(id, TicketAction.Close, "SIGNED-DEMO-JO-2026-001");
        await using (var db = factory.CreateDbContext()) { var t = await db.Tickets.SingleAsync(); Assert.Equal(TicketState.Closed, t.State); Assert.NotEmpty(t.CompletionSummary); Assert.NotEmpty(t.SignedJobOrder); Assert.Equal(7, await db.TicketEvents.CountAsync()); Assert.Equal(ConcernState.Closed, (await db.Concerns.SingleAsync()).State); }
        await Login("amara"); var client = await service.TicketAsync(id); Assert.DoesNotContain(client.Timeline, x => x.Internal || x.Text.Contains("Private"));
        await Login("coordinator"); await Update(id, TicketAction.Reopen, "Client reports recurrence"); Assert.Equal(TicketState.Assigned, (await service.TicketAsync(id)).Row.State); Assert.Equal(8, (await service.TicketAsync(id)).Timeline.Length);
    }
    [PostgreSqlFact] public async Task PaymentAndDuplicateTicketsAreRejectedAndUniqueConstraintIsReal()
    {
        await Login("amara"); var c = await Submit(ConcernCategory.BillingPaymentInquiry); await Login("admin"); var d = await service.ConcernAsync(c);
        await Assert.ThrowsAsync<BusinessException>(() => service.CreateTicketAsync(c, d.Row.Version));
        var id = await Ticket(); var t = await service.TicketAsync(id); d = await service.ConcernAsync(t.ConcernId);
        await Assert.ThrowsAsync<BusinessException>(() => service.CreateTicketAsync(d.Row.Id, d.Row.Version));
        await using var db = factory.CreateDbContext(); db.Tickets.Add(new() { ServiceConcernId = t.ConcernId }); await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
        await using var fresh = factory.CreateDbContext(); Assert.Equal(1, await fresh.Tickets.CountAsync());
    }
    [PostgreSqlFact] public async Task EssentialHistoryFailureRollsBackAlreadyWrittenStateAndAllowsRetry()
    {
        var id = await Ticket(); var plumber = (await service.PlumbersAsync()).First(x => x.Available); await Update(id, TicketAction.Assign, "Assign", plumber.Id); await Update(id, TicketAction.Start, "Start");
        var before = await service.TicketAsync(id);
        await using var db = factory.CreateDbContext();
        // A real PostgreSQL exception on the essential event INSERT, after the service's first SaveChanges.
        await db.Database.ExecuteSqlRawAsync("""
            CREATE FUNCTION reject_resolution_history() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN IF NEW."Action" = 'Resolve' THEN RAISE EXCEPTION 'Injected essential history failure'; END IF; RETURN NEW; END $$;
            CREATE TRIGGER fail_resolution_history BEFORE INSERT ON "TicketEvents" FOR EACH ROW EXECUTE FUNCTION reject_resolution_history();
            """);
        await Assert.ThrowsAsync<DbUpdateException>(() => service.UpdateTicketAsync(id, before.Row.Version, TicketAction.Resolve, "Completed fictional repair"));
        var after = await service.TicketAsync(id); Assert.Equal(before.Row.Version, after.Row.Version); Assert.Equal(TicketState.InProgress, after.Row.State); Assert.Empty(after.Summary); Assert.Equal(before.Timeline.Length, after.Timeline.Length);
        await using (var fresh = factory.CreateDbContext()) { Assert.Null((await fresh.Tickets.SingleAsync()).ResolvedAt); Assert.False(await fresh.Audits.AnyAsync(x => x.Operation == "Ticket Resolve")); }
        await db.Database.ExecuteSqlRawAsync("DROP TRIGGER fail_resolution_history ON \"TicketEvents\"; DROP FUNCTION reject_resolution_history();");
        await service.UpdateTicketAsync(id, before.Row.Version, TicketAction.Resolve, "Completed fictional repair"); Assert.Equal(TicketState.Resolved, (await service.TicketAsync(id)).Row.State);
    }
    [PostgreSqlFact] public async Task AccountIsolationAndPrivilegesAreEnforcedOnDirectCalls()
    {
        var id = await Ticket(); var t = await service.TicketAsync(id); var c = await service.ConcernAsync(t.ConcernId);
        await service.RespondAsync(c.Row.Id, c.Row.Version, "SECRET_INTERNAL", true, c.Row.Category, false);
        await Login("benito"); Assert.Empty((await service.ConcernsAsync()).Items); Assert.Empty((await service.TicketsAsync()).Items);
        await Assert.ThrowsAsync<BusinessException>(() => service.ConcernAsync(c.Row.Id)); await Assert.ThrowsAsync<BusinessException>(() => service.TicketAsync(id));
        await Assert.ThrowsAsync<BusinessException>(() => service.SubmitAsync(new(c.AccountId, ConcernCategory.OtherTechnicalConcern, "Attempt", "Invalid account", "location", "", "")));
        await Assert.ThrowsAsync<BusinessException>(() => service.ConcernsAsync(accountId: c.AccountId));
        await Assert.ThrowsAsync<BusinessException>(() => service.UpdateTicketAsync(id, t.Row.Version, TicketAction.Start, "Attempt"));
        await Login("viewer"); await Assert.ThrowsAsync<BusinessException>(() => service.RespondAsync(c.Row.Id, c.Row.Version, "Attempt", false, c.Row.Category, false)); await Assert.ThrowsAsync<BusinessException>(() => service.CreateTicketAsync(c.Row.Id, c.Row.Version));
        await Login("handler"); await Assert.ThrowsAsync<BusinessException>(() => service.UpdateTicketAsync(id, t.Row.Version, TicketAction.Start, "Attempt"));
        await Login("amara"); Assert.DoesNotContain((await service.ConcernAsync(c.Row.Id)).Timeline, x => x.Internal || x.Text.Contains("SECRET")); Assert.DoesNotContain((await service.OverviewAsync()).RecentActivity, x => x.Text.Contains("SECRET"));
    }
    [PostgreSqlFact] public async Task StaleUpdatesAndInvalidTransitionsDoNotChangeDatabase()
    {
        var id = await Ticket(); var before = await service.TicketAsync(id); var p = (await service.PlumbersAsync()).First(x => x.Available); await Update(id, TicketAction.Assign, "Assign", p.Id);
        await Assert.ThrowsAsync<BusinessException>(() => service.UpdateTicketAsync(id, before.Row.Version, TicketAction.Start, "Stale start"));
        var assigned = await service.TicketAsync(id); await Assert.ThrowsAsync<BusinessException>(() => service.UpdateTicketAsync(id, assigned.Row.Version, TicketAction.Close, "SIGNED-JO"));
        var after = await service.TicketAsync(id); Assert.Equal(TicketState.Assigned, after.Row.State); Assert.Equal(assigned.Row.Version, after.Row.Version); Assert.Equal(assigned.Timeline.Length, after.Timeline.Length);
    }
    [PostgreSqlFact] public async Task SeedingIsIdempotentAndDoesNotResetOperationalRecords()
    {
        await Login("amara"); var c = await Submit(); await using var db = factory.CreateDbContext(); await DemoSeeder.SeedAsync(db, true); await DemoSeeder.SeedAsync(db, true);
        Assert.Equal(7, await db.Users.CountAsync()); Assert.Equal(3, await db.Accounts.CountAsync()); Assert.Equal(3, await db.Plumbers.CountAsync()); Assert.Equal(2, await db.Concerns.CountAsync()); Assert.True(await db.Concerns.AnyAsync(x => x.Id == c)); Assert.All(await db.Users.ToArrayAsync(), x => Assert.NotEqual(DemoSeeder.Password, x.PasswordHash));
    }
}
