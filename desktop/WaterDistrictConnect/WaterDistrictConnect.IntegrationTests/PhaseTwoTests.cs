using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql;
using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;
using WaterDistrictConnect.Core.Persistence;
using WaterDistrictConnect.ViewModels;

namespace WaterDistrictConnect.IntegrationTests;

public sealed class PhaseTwoFactAttribute : FactAttribute
{
    public PhaseTwoFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("MWD_TEST_ADMIN")))
            Skip = "Set MWD_TEST_ADMIN to a PostgreSQL server that permits disposable test database creation.";
    }
}

[Trait("Phase", "2")]
public sealed class PhaseTwoTests : IAsyncLifetime
{
    [PhaseTwoFact] public async Task BillingEnforcesOwnershipPaymentsAndDuplicateMonths()
    {
        await Login("admin");
        var account = (await service.AccountsAsync()).Single(x => x.Number == "000101");
        await service.SaveBillAsync(null, null, account.Id, new(2026, 11, 12), new(2026, 11, 25), 350.25m, false);
        var bill = Assert.Single(await service.BillsAsync());
        Assert.Equal(new DateOnly(2026, 11, 1), bill.Month);
        await Assert.ThrowsAsync<BusinessException>(() => service.SaveBillAsync(null, null, account.Id, bill.Month, bill.DueDate, 10m, false));
        await Login("amara");
        Assert.Single(await service.BillsAsync());
        await Assert.ThrowsAsync<BusinessException>(() => service.SaveBillAsync(bill.Id, bill.Version, account.Id, bill.Month, bill.DueDate, 1m, true));
        await Login("benito"); Assert.Empty(await service.BillsAsync());
        await Login("viewer"); await Assert.ThrowsAsync<BusinessException>(() => service.BillsAsync());
        await Login("admin");
        await service.SaveBillAsync(bill.Id, bill.Version, account.Id, bill.Month, bill.DueDate, bill.Amount, true);
        await Assert.ThrowsAsync<BusinessException>(() => service.SaveBillAsync(bill.Id, bill.Version, account.Id, bill.Month, bill.DueDate, 1m, false));
        await Login("amara"); Assert.Equal("Paid", Assert.Single(await service.BillsAsync()).Status);
    }
    private string admin = "", database = "";
    private TestFactory factory = null!;
    private readonly Session session = new();
    private AuthenticationService auth = null!;
    private WaterService service = null!;
    public async Task InitializeAsync()
    {
        admin = Environment.GetEnvironmentVariable("MWD_TEST_ADMIN") ?? "";
        if (admin == "") return;
        // Never connect the application service to the supplied database. Only a generated database is migrated/seeded.
        database = "mwd_phase2_" + Guid.NewGuid().ToString("N");
        await using var con = new NpgsqlConnection(admin); await con.OpenAsync();
        await using var cmd = new NpgsqlCommand($"CREATE DATABASE \"{database}\"", con); await cmd.ExecuteNonQueryAsync();
        factory = new(new NpgsqlConnectionStringBuilder(admin) { Database = database }.ConnectionString);
        await using var db = factory.CreateDbContext(); await db.Database.MigrateAsync(); await DemoSeeder.SeedAsync(db);
        auth = new(factory, session); service = new(factory, session);
    }
    public async Task DisposeAsync()
    {
        session.Clear();
        if (database == "") return;
        if (!System.Text.RegularExpressions.Regex.IsMatch(database, "^mwd_phase2_[a-f0-9]{32}$"))
            throw new InvalidOperationException("Refusing to remove an unexpected database.");
        await using var con = new NpgsqlConnection(admin); await con.OpenAsync();
        await using var cmd = new NpgsqlCommand($"DROP DATABASE \"{database}\" WITH (FORCE)", con); await cmd.ExecuteNonQueryAsync();
    }
    private Task<Identity> Login(string name) => auth.LoginAsync(name, DemoSeeder.Password);
    private static ConcernInput Input(ConcernCategory category = ConcernCategory.GeneralInquiry) =>
        new(null, category, "Fictional service question", "Please explain the fictional service procedure.", "12 Fictional Street", "", "Ignored by client", Guid.NewGuid());
    private async Task<Guid> Submit(ConcernCategory category = ConcernCategory.GeneralInquiry)
    { await Login("amara"); return await service.SubmitAsync(Input(category)); }
    private async Task Apply(Guid id, ConcernAction action, string text = "Meaningful fictional office explanation.", ConcernCategory? category = null)
    { var d = await service.ConcernAsync(id); await service.ProcessConcernAsync(id, d.Row.Version, action, text, category ?? d.Row.Category); }

    [PhaseTwoFact] public async Task ClientSubmissionPersistsReceiptAndSurvivesNewSession()
    {
        var id = await Submit(); var d = await service.ConcernAsync(id);
        Assert.Matches("^MWD-[0-9]+$", d.Row.Reference); Assert.Equal(ConcernState.Submitted, d.Row.State);
        Assert.Equal("000101", d.Row.AccountNumber); Assert.Equal("Desktop Client", d.Channel);
        Assert.Null(d.FirstResponse); Assert.Equal("Receipt", Assert.Single(d.Timeline).Kind);
        await using var db = factory.CreateDbContext(); var c = await db.Concerns.SingleAsync();
        Assert.Equal(session.UserId, c.RecordedById); Assert.Equal(TimeSpan.Zero, c.SubmittedAt.Offset);
        Assert.Single(await db.Audits.ToArrayAsync()); Assert.Equal(c.Id, (await db.ConcernEvents.SingleAsync()).ServiceConcernId);
        var next = new Session(); await new AuthenticationService(factory, next).LoginAsync("amara", DemoSeeder.Password);
        Assert.Equal(d.Row.Reference, (await new WaterService(factory, next).ConcernAsync(id)).Row.Reference);
    }
    [PhaseTwoFact] public async Task InvalidFieldsAndIneligibleAccountsLeaveNoRows()
    {
        await Login("amara"); var i = Input();
        foreach (var invalid in new[] { i with { Subject = " " }, i with { Subject = new('s', 161) },
            i with { Description = "" }, i with { Description = new('d', 4001) }, i with { Location = " " },
            i with { Location = new('l', 301) }, i with { Contact = new('c', 201) }, i with { Category = (ConcernCategory)99 },
            i with { AccountId = Guid.NewGuid() }, i with { SubmissionKey = Guid.Empty } })
            await Assert.ThrowsAsync<BusinessException>(() => service.SubmitAsync(invalid));
        await using var db = factory.CreateDbContext(); var ownership = await db.Ownerships.SingleAsync(x => x.UserId == session.UserId);
        db.Ownerships.Remove(ownership); await db.SaveChangesAsync();
        await Assert.ThrowsAsync<BusinessException>(() => service.SubmitAsync(i));
        Assert.Empty(await db.Concerns.ToArrayAsync()); Assert.Empty(await db.ConcernEvents.ToArrayAsync()); Assert.Empty(await db.Audits.ToArrayAsync());
    }
    [PhaseTwoFact] public async Task CrossAccountDirectCallsAreRejected()
    {
        var id = await Submit(); var d = await service.ConcernAsync(id); await Login("benito");
        Assert.Empty((await service.ConcernsAsync()).Items); Assert.Equal(0, (await service.ConcernOverviewAsync()).Total);
        await Assert.ThrowsAsync<BusinessException>(() => service.ConcernAsync(id));
        await Assert.ThrowsAsync<BusinessException>(() => service.ConcernsAsync(accountId: d.AccountId));
        await Assert.ThrowsAsync<BusinessException>(() => service.SubmitAsync(Input() with { AccountId = d.AccountId }));
        await Assert.ThrowsAsync<BusinessException>(() => service.ProcessConcernAsync(id, d.Row.Version, ConcernAction.Respond, "Unauthorized direct response", d.Row.Category));
    }
    [PhaseTwoFact] public async Task OfficeIntakePreservesSelectedAccountActorAndActualChannel()
    {
        var who = await Login("handler"); var account = (await service.AccountsAsync("000102")).Single();
        foreach (var channel in new[] { "Telephone", "Walk-in", "Other" })
        {
            var id = await service.SubmitAsync(Input() with { AccountId = account.Id, Channel = channel });
            var d = await service.ConcernAsync(id); Assert.Equal(account.Id, d.AccountId); Assert.Equal(channel, d.Channel);
            Assert.Equal(who.Name, d.RecordedBy); Assert.Null(d.FirstResponse);
        }
        await Assert.ThrowsAsync<BusinessException>(() => service.SubmitAsync(Input() with { AccountId = account.Id, Channel = "Desktop Client" }));
        await using var db = factory.CreateDbContext(); Assert.All(await db.Concerns.ToArrayAsync(), x => Assert.Equal(who.Id, x.RecordedById));
        await Login("benito"); Assert.Equal(3, (await service.ConcernsAsync()).Total);
        Assert.All((await service.ConcernAsync((await service.ConcernsAsync()).Items[0].Id)).Timeline, x => Assert.Contains("on behalf", x.Text));
    }
    [PhaseTwoFact] public async Task ReadOnlyAndRevokedPermissionsCannotMutate()
    {
        var id = await Submit(); await Login("viewer"); var d = await service.ConcernAsync(id);
        foreach (var action in Enum.GetValues<ConcernAction>())
            await Assert.ThrowsAsync<BusinessException>(() => service.ProcessConcernAsync(id, d.Row.Version, action, "Unauthorized office decision", d.Row.Category));
        await Assert.ThrowsAsync<BusinessException>(() => service.SubmitAsync(Input() with { AccountId = d.AccountId, Channel = "Telephone" }));
        await Login("handler"); await using var db = factory.CreateDbContext();
        var p = await db.Set<RolePermission>().SingleAsync(x => x.Role.Name == "Concern handler" && x.Permission == Permissions.Respond);
        db.Remove(p); await db.SaveChangesAsync();
        await Assert.ThrowsAsync<BusinessException>(() => Apply(id, ConcernAction.Respond));
        session.Clear(); await Assert.ThrowsAsync<BusinessException>(() => service.ConcernAsync(id));
    }
    [PhaseTwoFact] public async Task HumanResponseTimingAndClientVisibilityAreExact()
    {
        var id = await Submit(); await Login("handler"); await service.ConcernAsync(id);
        await Apply(id, ConcernAction.Review, "PRIVATE_REVIEW internal office assessment");
        await Apply(id, ConcernAction.InternalNote, "PRIVATE_NOTE internal scheduling detail");
        await Apply(id, ConcernAction.Reclassify, "PRIVATE_CLASS correcting the billing classification", ConcernCategory.BillingPaymentInquiry);
        Assert.Null((await service.ConcernAsync(id)).FirstResponse);
        await Apply(id, ConcernAction.Respond, "We have reviewed your billing question."); var first = (await service.ConcernAsync(id)).FirstResponse;
        Assert.NotNull(first); await Apply(id, ConcernAction.Respond, "A second customer-visible human response.");
        Assert.Equal(first, (await service.ConcernAsync(id)).FirstResponse);
        await Login("amara"); var d = await service.ConcernAsync(id);
        Assert.Equal(3, d.Timeline.Length); Assert.DoesNotContain(d.Timeline, x => x.Internal || x.Text.Contains("PRIVATE") || x.Kind == "Classification corrected");
        Assert.DoesNotContain((await service.OverviewAsync()).RecentActivity, x => x.Text.Contains("PRIVATE"));
        Assert.DoesNotContain((await service.ConcernOverviewAsync()).Activity!, x => x.Event.Internal || x.Event.Text.Contains("PRIVATE"));
        Assert.Equal(ConcernCategory.BillingPaymentInquiry, d.Row.Category);
        await using var db = factory.CreateDbContext(); var history = await db.ConcernEvents.OrderBy(x => x.At).ToArrayAsync();
        Assert.Equal(6, history.Length); Assert.All(history, x => { Assert.NotEqual(Guid.Empty, x.ActorId); Assert.Equal(id, x.ServiceConcernId); Assert.Equal(TimeSpan.Zero, x.At.Offset); });
        var classification = history.Single(x => x.Kind == "Classification corrected");
        Assert.Equal(ConcernCategory.GeneralInquiry, classification.PreviousCategory); Assert.Equal(ConcernCategory.BillingPaymentInquiry, classification.NewCategory);
    }
    [PhaseTwoFact] public async Task NontechnicalLifecycleRequiresReasonsAndPreservesReopenHistory()
    {
        var id = await Submit(); await Login("handler");
        await Assert.ThrowsAsync<BusinessException>(() => Apply(id, ConcernAction.Close));
        await Apply(id, ConcernAction.Review); await Assert.ThrowsAsync<BusinessException>(() => Apply(id, ConcernAction.Resolve, "short"));
        await Apply(id, ConcernAction.Resolve); Assert.Equal(ConcernState.Resolved, (await service.ConcernAsync(id)).Row.State);
        await Apply(id, ConcernAction.Close); Assert.Equal(ConcernState.Closed, (await service.ConcernAsync(id)).Row.State);
        await Assert.ThrowsAsync<BusinessException>(() => Apply(id, ConcernAction.Reopen, ""));
        await Apply(id, ConcernAction.Reopen, "The client requests further clarification.");
        var d = await service.ConcernAsync(id); Assert.Equal(ConcernState.UnderReview, d.Row.State);
        Assert.Contains(d.Timeline, x => x.Kind == "Resolve" && x.NewState == ConcernState.Resolved);
        Assert.Contains(d.Timeline, x => x.Kind == "Close" && x.NewState == ConcernState.Closed);
        Assert.Contains(d.Timeline, x => x.Kind == "Reopen" && x.PreviousState == ConcernState.Closed);
    }
    [PhaseTwoFact] public async Task TechnicalConcernsCannotBypassPhaseThree()
    {
        foreach (var category in ConcernLabels.Categories.Where(ConcernLabels.Technical))
        {
            var id = await Submit(category); await Login("admin"); await Apply(id, ConcernAction.Review);
            await Assert.ThrowsAsync<BusinessException>(() => Apply(id, ConcernAction.Resolve));
            await Assert.ThrowsAsync<BusinessException>(() => Apply(id, ConcernAction.Close));
            var current = await service.ConcernAsync(id);
            await Assert.ThrowsAsync<BusinessException>(() => service.CreateTicketAsync(id, current.Row.Version));
            Assert.Equal(ConcernState.UnderReview, (await service.ConcernAsync(id)).Row.State);
        }
    }
    [PhaseTwoFact] public async Task StaleAndRacingUpdatesDoNotOverwriteHistory()
    {
        var id = await Submit(); await Login("handler"); var before = await service.ConcernAsync(id);
        var start = new TaskCompletionSource();
        async Task<bool> TryUpdate(string text)
        {
            await start.Task;
            try { await service.ProcessConcernAsync(id, before.Row.Version, ConcernAction.Respond, text, before.Row.Category); return true; }
            catch (BusinessException) { return false; } catch (DbUpdateConcurrencyException) { return false; }
        }
        var a = TryUpdate("First concurrent human office response"); var b = TryUpdate("Second concurrent human office response"); start.SetResult();
        Assert.Single(await Task.WhenAll(a, b), x => x);
        var after = await service.ConcernAsync(id); Assert.Equal(2, after.Timeline.Length);
        await Assert.ThrowsAsync<BusinessException>(() => service.ProcessConcernAsync(id, before.Row.Version, ConcernAction.InternalNote, "Stale internal note must not persist", before.Row.Category));
        Assert.Equal(after.Row.Version, (await service.ConcernAsync(id)).Row.Version);
    }
    [PhaseTwoFact] public async Task ConcurrentReferencesAndIdempotentRetriesAreSafe()
    {
        await Login("amara"); var input = Input();
        var retryIds = await Task.WhenAll(Enumerable.Range(0, 4).Select(_ => service.SubmitAsync(input)));
        Assert.Single(retryIds.Distinct());
        await Assert.ThrowsAsync<BusinessException>(() => service.SubmitAsync(input with { Subject = "Changed retry content" }));
        var ids = await Task.WhenAll(Enumerable.Range(0, 10).Select(_ => service.SubmitAsync(Input())));
        await using var db = factory.CreateDbContext(); Assert.Equal(11, await db.Concerns.CountAsync()); Assert.Equal(11, await db.ConcernEvents.CountAsync());
        Assert.Equal(11, (await db.Concerns.Select(x => x.Reference).ToArrayAsync()).Distinct().Count());
        var c = await db.Concerns.FirstAsync(); db.Concerns.Add(new() { Reference = c.Reference, CustomerAccountId = c.CustomerAccountId, RecordedById = c.RecordedById, Subject = "Duplicate reference", Description = "Database uniqueness must reject this.", Location = "Fictional location" });
        await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
    }
    [PhaseTwoFact] public async Task DatabaseConstraintsRejectInvalidConcernRows()
    {
        await Login("amara"); var account = Assert.Single(await service.AccountsAsync());
        foreach (var invalid in new[] { "category", "state", "channel", "content", "foreign-key" })
        {
            await using var db = factory.CreateDbContext();
            var c = new ServiceConcern { CustomerAccountId = account.Id, RecordedById = session.UserId!.Value, Subject = "Constraint fixture", Description = "Fictional database constraint fixture", Location = "Fictional location" };
            switch (invalid)
            {
                case "category": c.Category = (ConcernCategory)99; break;
                case "state": c.State = (ConcernState)99; break;
                case "channel": c.IntakeChannel = (IntakeChannel)99; break;
                case "content": c.Subject = " "; break;
                case "foreign-key": c.CustomerAccountId = Guid.NewGuid(); break;
            }
            db.Concerns.Add(c); await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
        }
        await using var fresh = factory.CreateDbContext(); Assert.Empty(await fresh.Concerns.ToArrayAsync());
    }
    [PhaseTwoFact] public async Task RealHistoryInsertFailureRollsBackReceiptAndOfficeState()
    {
        await Login("amara"); var input = Input();
        await using var db = factory.CreateDbContext();
        await db.Database.ExecuteSqlRawAsync("""
            CREATE FUNCTION reject_concern_history() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN RAISE EXCEPTION 'Injected concern history failure'; END $$;
            CREATE TRIGGER fail_concern_history BEFORE INSERT ON "ConcernEvents" FOR EACH ROW EXECUTE FUNCTION reject_concern_history();
            """);
        await Assert.ThrowsAsync<DbUpdateException>(() => service.SubmitAsync(input));
        Assert.Empty(await db.Concerns.ToArrayAsync()); Assert.Empty(await db.Audits.ToArrayAsync());
        await db.Database.ExecuteSqlRawAsync("DROP TRIGGER fail_concern_history ON \"ConcernEvents\"");
        var id = await service.SubmitAsync(input); await Login("handler"); var before = await service.ConcernAsync(id);
        await db.Database.ExecuteSqlRawAsync("CREATE TRIGGER fail_concern_history BEFORE INSERT ON \"ConcernEvents\" FOR EACH ROW EXECUTE FUNCTION reject_concern_history()");
        await Assert.ThrowsAsync<DbUpdateException>(() => Apply(id, ConcernAction.Respond));
        var after = await service.ConcernAsync(id); Assert.Equal(before.Row.Version, after.Row.Version); Assert.Equal(before.Row.State, after.Row.State); Assert.Null(after.FirstResponse); Assert.Single(after.Timeline);
        Assert.Equal(1, await db.Audits.CountAsync());
        await db.Database.ExecuteSqlRawAsync("DROP TRIGGER fail_concern_history ON \"ConcernEvents\"");
        await Apply(id, ConcernAction.Respond); Assert.NotNull((await service.ConcernAsync(id)).FirstResponse);
    }
    [PhaseTwoFact] public async Task FiltersPaginationAndCountsUsePersistedOwnership()
    {
        await Login("amara");
        for (var n = 0; n < 23; n++) await service.SubmitAsync(Input(n < 21 ? ConcernCategory.GeneralInquiry : ConcernCategory.WaterLeak) with { Subject = $"Searchable question {n}" });
        var first = await service.ConcernsAsync("Searchable", ConcernCategory.GeneralInquiry, ConcernState.Submitted);
        Assert.Equal(21, first.Total); Assert.Equal(20, first.Items.Length);
        var second = await service.ConcernsAsync("Searchable", ConcernCategory.GeneralInquiry, ConcernState.Submitted, 2); Assert.Single(second.Items); Assert.DoesNotContain(second.Items[0].Id, first.Items.Select(x => x.Id));
        Assert.Single((await service.ConcernsAsync(first.Items[0].Reference)).Items);
        Assert.Empty((await service.ConcernsAsync(state: ConcernState.Closed)).Items);
        Assert.Equal(23, (await service.ConcernOverviewAsync()).Total);
        await Login("benito"); Assert.Empty((await service.ConcernsAsync()).Items);
        await Login("viewer"); Assert.Equal(23, (await service.ConcernOverviewAsync()).Total);
    }

    [PhaseTwoFact] public async Task UpgradePreservesExistingConcernsAndIntakeText()
    {
        var upgradeName = "mwd_phase2_" + Guid.NewGuid().ToString("N");
        await using var con = new NpgsqlConnection(admin); await con.OpenAsync();
        await using (var create = new NpgsqlCommand($"CREATE DATABASE \"{upgradeName}\"", con)) await create.ExecuteNonQueryAsync();
        try
        {
            var upgradeFactory = new TestFactory(new NpgsqlConnectionStringBuilder(admin) { Database = upgradeName }.ConnectionString);
            await using var db = upgradeFactory.CreateDbContext();
            await db.GetService<IMigrator>().MigrateAsync("20261123143321_InitialScope");
            // Write through SQL because this is intentionally the old schema, before the new model can be used.
            var actor = Guid.NewGuid(); var account = Guid.NewGuid(); var concern = Guid.NewGuid();
            await db.Database.ExecuteSqlInterpolatedAsync($"INSERT INTO \"Users\" (\"Id\",\"Username\",\"PasswordHash\",\"DisplayName\",\"Active\") VALUES ({actor},'legacy','unused','Fictional legacy actor',true)");
            await db.Database.ExecuteSqlInterpolatedAsync($"INSERT INTO \"Accounts\" (\"Id\",\"Number\",\"Name\",\"Address\") VALUES ({account},'LEGACY-1','Fictional legacy account','Fictional address')");
            await db.Database.ExecuteSqlInterpolatedAsync($"INSERT INTO \"Concerns\" (\"Id\",\"Reference\",\"CustomerAccountId\",\"RecordedById\",\"IntakeChannel\",\"Category\",\"State\",\"Subject\",\"Description\",\"Location\",\"Contact\",\"SubmittedAt\",\"Version\") VALUES ({concern},'MWD-150000',{account},{actor},'Office visit',0,0,'Keep legacy concern','Keep the original description','Fictional address','',{DateTimeOffset.UtcNow},{Guid.NewGuid()})");
            await db.Database.MigrateAsync();
            var saved = await db.Concerns.SingleAsync(); Assert.Equal(concern, saved.Id); Assert.Equal("Keep the original description", saved.Description);
            Assert.Equal("Office visit", saved.LegacyIntakeChannel); Assert.Equal(IntakeChannel.WalkIn, saved.IntakeChannel); Assert.NotEqual(Guid.Empty, saved.SubmissionKey);
            db.Concerns.Add(new() { CustomerAccountId = account, RecordedById = actor, Subject = "Next reference", Description = "Reference after upgrade", Location = "Fictional address" });
            await db.SaveChangesAsync(); Assert.Contains(await db.Concerns.ToArrayAsync(), x => x.Reference == "MWD-150001");
        }
        finally
        {
            await using var drop = new NpgsqlCommand($"DROP DATABASE \"{upgradeName}\" WITH (FORCE)", con); await drop.ExecuteNonQueryAsync();
        }
    }

    [PhaseTwoFact] public async Task ProductionViewModelsCompleteClientOfficeClientAndRestartSequence()
    {
        var setup = new DatabaseSetup(factory, new AppConfiguration("Host=unused;Database=unused;Username=unused"));
        var root = new RootViewModel(auth, service, setup, session, new Confirm(), new AppConfiguration((string?)null));
        async Task<WorkspaceViewModel> SignIn(string name)
        {
            var login = Assert.IsType<LoginViewModel>(root.Current); login.Username = name; login.Password = DemoSeeder.Password;
            await login.LoginCommand.ExecuteAsync(null); Assert.Empty(login.Error); return Assert.IsType<WorkspaceViewModel>(root.Current);
        }
        var client = await SignIn("amara"); client.Navigate("submit");
        var submit = Assert.IsType<SubmitViewModel>(client.Page);
        // Constructor loading is asynchronous. Explicitly await the actual busy operation before using the form.
        await WaitUntilIdle(submit); Assert.Equal("000101", submit.Account?.Number); Assert.NotEmpty(submit.Location);
        submit.Category = submit.Categories.Single(x => x.Value == ConcernCategory.GeneralInquiry);
        submit.Subject = "ViewModel demonstration concern"; submit.Description = "A fictional question submitted from the actual Phase 2 form.";
        await submit.ReviewCommand.ExecuteAsync(null); Assert.Empty(submit.Error); Assert.True(submit.IsReviewing); Assert.False(submit.IsEditing);
        submit.EditCommand.Execute(null); Assert.True(submit.IsEditing); Assert.Equal("ViewModel demonstration concern", submit.Subject);
        await submit.ReviewCommand.ExecuteAsync(null); Assert.True(submit.IsReviewing);
        await submit.SubmitCommand.ExecuteAsync(null); Assert.Empty(submit.Error); Assert.NotNull(submit.SavedId); Assert.Contains("MWD-", submit.Success);
        var id = submit.SavedId!.Value; submit.ViewSavedCommand.Execute(null);
        var clientDetail = Assert.IsType<ConcernDetailViewModel>(client.Page); await WaitUntilIdle(clientDetail); Assert.False(clientDetail.CanRespond);
        client.LogoutCommand.Execute(null);
        var office = await SignIn("handler"); office.Navigate("concerns"); var queue = Assert.IsType<ConcernsViewModel>(office.Page); await WaitUntilIdle(queue);
        queue.Search = "ViewModel demonstration"; await queue.RefreshCommand.ExecuteAsync(null); Assert.Single(queue.Rows);
        queue.OpenCommand.Execute(queue.Rows[0]); var response = Assert.IsType<ConcernDetailViewModel>(office.Page); await WaitUntilIdle(response);
        response.Action = response.Actions.Single(x => x.Value == ConcernAction.Respond); response.Response = "We reviewed the fictional concern and will provide assistance.";
        await response.RespondCommand.ExecuteAsync(null); Assert.Empty(response.Error); Assert.NotNull(response.Detail?.FirstResponse);
        office.LogoutCommand.Execute(null); client = await SignIn("amara"); client.OpenConcern(id);
        clientDetail = Assert.IsType<ConcernDetailViewModel>(client.Page); await WaitUntilIdle(clientDetail);
        Assert.Contains(clientDetail.Detail!.Timeline, x => x.Text.Contains("will provide assistance"));
        client.LogoutCommand.Execute(null); var other = await SignIn("benito"); other.OpenConcern(id);
        var denied = Assert.IsType<ConcernDetailViewModel>(other.Page); await WaitUntilIdle(denied, expectError: true); Assert.Null(denied.Detail); Assert.Contains("unavailable", denied.Error);
        other.LogoutCommand.Execute(null);
        var restartSession = new Session(); var restartService = new WaterService(factory, restartSession);
        await new AuthenticationService(factory, restartSession).LoginAsync("amara", DemoSeeder.Password);
        Assert.Contains((await restartService.ConcernAsync(id)).Timeline, x => x.Kind == "Human response");
    }
    private static async Task WaitUntilIdle(ViewModelBase vm, bool expectError = false)
    {
        var timeout = DateTime.UtcNow.AddSeconds(10);
        while (vm.IsBusy && DateTime.UtcNow < timeout) await Task.Delay(10);
        Assert.False(vm.IsBusy); if (!expectError) Assert.Empty(vm.Error);
    }
    private sealed class Confirm : IConfirmationService { public Task<bool> ConfirmAsync(string title, string message) => Task.FromResult(true); }
}
