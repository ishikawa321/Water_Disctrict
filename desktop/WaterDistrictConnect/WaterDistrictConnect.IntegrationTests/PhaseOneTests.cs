using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;
using WaterDistrictConnect.Core.Persistence;
using WaterDistrictConnect.ViewModels;

namespace WaterDistrictConnect.IntegrationTests;

public sealed class PhaseOneFactAttribute : FactAttribute
{
    public PhaseOneFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("MWD_PHASE1_TEST_CONNECTION")))
            Skip = "Set MWD_PHASE1_TEST_CONNECTION to the dedicated mwd_phase1_test PostgreSQL database. No database is dropped or reset.";
    }
}
[Trait("Phase", "1")]
public sealed class PhaseOneTests : IAsyncLifetime
{
    private TestFactory factory = null!;
    private readonly Session session = new();
    private AuthenticationService auth = null!;
    private WaterService service = null!;
    public async Task InitializeAsync()
    {
        var connection = Environment.GetEnvironmentVariable("MWD_PHASE1_TEST_CONNECTION");
        if (string.IsNullOrWhiteSpace(connection)) return;
        var builder = new NpgsqlConnectionStringBuilder(connection);
        if (builder.Database != "mwd_phase1_test") throw new InvalidOperationException("Phase 1 tests require the dedicated database named mwd_phase1_test. Refusing application database access.");
        factory = new(connection); await using var db = factory.CreateDbContext();
        await db.Database.MigrateAsync(); await DemoSeeder.SeedAsync(db, false);
        auth = new(factory, session); service = new(factory, session);
    }
    public Task DisposeAsync() { session.Clear(); return Task.CompletedTask; } // No database deletion or cleanup of normal records.
    [PhaseOneFact] public async Task AllSevenDemoIdentitiesAuthenticateWithExpectedAccessAndDistinctOwnership()
    {
        var ids = new List<Guid>();
        foreach (var username in new[] { "admin", "handler", "coordinator", "viewer", "amara", "benito", "clara" })
        {
            var who = await auth.LoginAsync(username, DemoSeeder.Password);
            Assert.Equal(who.Id, session.UserId); Assert.NotEmpty(who.RoleLabel);
            if (who.IsClient) { var account = Assert.Single(await service.AccountsAsync()); Assert.Equal(who.AccountId, account.Id); ids.Add(account.Id); await Assert.ThrowsAsync<BusinessException>(() => service.PlumbersAsync()); }
            else { Assert.Equal(3, (await service.AccountsAsync()).Length); Assert.Equal(3, (await service.PlumbersAsync()).Length); }
            if (username == "viewer") { Assert.False(who.Has(Permissions.Intake)); Assert.False(who.Has(Permissions.Respond)); Assert.False(who.Has(Permissions.Repair)); }
            if (username == "handler") { Assert.True(who.Has(Permissions.Intake)); Assert.True(who.Has(Permissions.Respond)); Assert.False(who.Has(Permissions.Repair)); }
            if (username == "coordinator") { Assert.True(who.Has(Permissions.Repair)); Assert.False(who.Has(Permissions.Intake)); }
        }
        Assert.Equal(3, ids.Distinct().Count());
    }
    [PhaseOneFact] public async Task WrongPasswordAndUnknownUsernameClearPriorSession()
    {
        await auth.LoginAsync("admin", DemoSeeder.Password);
        await Assert.ThrowsAsync<BusinessException>(() => auth.LoginAsync("admin", "incorrect")); Assert.Null(session.UserId);
        await Assert.ThrowsAsync<BusinessException>(() => auth.LoginAsync("no-such-demo-user", DemoSeeder.Password)); Assert.Null(session.UserId);
        var who = await auth.LoginAsync(" AMARA ", DemoSeeder.Password); Assert.Equal("amara", who.Username);
    }
    [PhaseOneFact] public async Task InactiveUsersAreRejectedAndActiveSessionsAreRechecked()
    {
        await using var db = factory.CreateDbContext();
        var user = new User { Username = "phase1-" + Guid.NewGuid().ToString("N"), DisplayName = "Disposable Phase 1 identity", Active = true };
        user.PasswordHash = new PasswordHasher<User>().HashPassword(user, DemoSeeder.Password);
        user.Roles.Add(new() { RoleId = (await db.Roles.SingleAsync(x => x.Name == "Office viewer")).Id }); db.Users.Add(user); await db.SaveChangesAsync();
        await auth.LoginAsync(user.Username, DemoSeeder.Password); user.Active = false; await db.SaveChangesAsync();
        await Assert.ThrowsAsync<BusinessException>(() => service.AccountsAsync());
        await Assert.ThrowsAsync<BusinessException>(() => auth.LoginAsync(user.Username, DemoSeeder.Password)); Assert.Null(session.UserId);
    }
    [PhaseOneFact] public async Task RepeatedSeedingPreservesIdsHashesOwnershipAndExistingOperationalRows()
    {
        await using var db = factory.CreateDbContext();
        if (!await db.Concerns.AnyAsync(x => x.Reference == "C-PHASE1-KEEP"))
        {
            var actor = await db.Users.SingleAsync(x => x.Username == "amara");
            var sentinel = new ServiceConcern { Reference = "C-PHASE1-KEEP", CustomerAccountId = (await db.Accounts.SingleAsync(x => x.Number == "000101")).Id, RecordedById = actor.Id, Subject = "Seeding preservation fixture", Description = "Existing fictional record must survive repeated foundation seeding.", Location = "Fictional test address" };
            sentinel.Events.Add(new() { ActorId = actor.Id, Kind = "Receipt", Text = "Fictional preservation fixture receipt." });
            db.Concerns.Add(sentinel); await db.SaveChangesAsync();
        }
        var before = await db.Users.AsNoTracking().OrderBy(x => x.Username).Select(x => new { x.Id, x.Username, x.PasswordHash, x.Active }).ToArrayAsync();
        var accounts = await db.Accounts.AsNoTracking().OrderBy(x => x.Number).Select(x => new { x.Id, x.Number }).ToArrayAsync();
        var resources = await db.Plumbers.AsNoTracking().OrderBy(x => x.Name).Select(x => x.Id).ToArrayAsync();
        var concerns = await db.Concerns.CountAsync(); var tickets = await db.Tickets.CountAsync();
        await DemoSeeder.SeedAsync(db, false); await DemoSeeder.SeedAsync(db, false);
        await using var fresh = factory.CreateDbContext();
        Assert.Equal(before, await fresh.Users.AsNoTracking().OrderBy(x => x.Username).Select(x => new { x.Id, x.Username, x.PasswordHash, x.Active }).ToArrayAsync());
        Assert.Equal(accounts, await fresh.Accounts.AsNoTracking().OrderBy(x => x.Number).Select(x => new { x.Id, x.Number }).ToArrayAsync());
        Assert.Equal(resources, await fresh.Plumbers.AsNoTracking().OrderBy(x => x.Name).Select(x => x.Id).ToArrayAsync());
        Assert.Equal(3, await fresh.Ownerships.CountAsync()); Assert.Equal(5, await fresh.Roles.CountAsync());
        Assert.Equal(concerns, await fresh.Concerns.CountAsync()); Assert.Equal(tickets, await fresh.Tickets.CountAsync());
        Assert.True(await fresh.Concerns.AnyAsync(x => x.Reference == "C-PHASE1-KEEP" && x.Description == "Existing fictional record must survive repeated foundation seeding."));
        Assert.All(await fresh.Users.ToArrayAsync(), x => { Assert.NotEqual(DemoSeeder.Password, x.PasswordHash); Assert.DoesNotContain(DemoSeeder.Password, x.PasswordHash); });
    }
    [PhaseOneFact] public async Task RootLoginAndLogoutDiscardWorkspaceAndRejectLaterServiceCalls()
    {
        var setup = new DatabaseSetup(factory, new AppConfiguration("Host=unused;Database=unused;Username=unused"));
        var root = new RootViewModel(auth, service, setup, session, new NoConfirmation(), new AppConfiguration((string?)null));
        var login = Assert.IsType<LoginViewModel>(root.Current); login.Username = "amara"; login.Password = DemoSeeder.Password;
        await login.LoginCommand.ExecuteAsync(null); Assert.Empty(login.Error); Assert.Empty(login.Password);
        var shell = Assert.IsType<WorkspaceViewModel>(root.Current); Assert.True(shell.Who.IsClient); Assert.Equal(["overview", "submit", "concerns", "accounts"], shell.Navigation.Select(x => x.Key));
        shell.LogoutCommand.Execute(null); Assert.Null(session.UserId); var nextLogin = Assert.IsType<LoginViewModel>(root.Current); Assert.Empty(nextLogin.Password);
        await Assert.ThrowsAsync<BusinessException>(() => service.AccountsAsync());
    }
    [PhaseOneFact] public async Task LoginViewModelReportsRealConnectionFailureWithoutLosingInput()
    {
        var config = new AppConfiguration("Host=127.0.0.1;Port=1;Database=mwd_phase1_test;Username=unavailable;Timeout=1;Pooling=false");
        var unavailable = new ConfiguredContextFactory(config);
        var login = new LoginViewModel(new(unavailable, session), new(unavailable, config), false, _ => throw new Exception("Unexpected login")) { Username = "admin", Password = DemoSeeder.Password };
        await login.LoginCommand.ExecuteAsync(null);
        Assert.Contains("Cannot reach PostgreSQL", login.Error); Assert.False(login.IsBusy); Assert.Equal(DemoSeeder.Password, login.Password); Assert.Null(session.UserId);
    }
    private sealed class NoConfirmation : IConfirmationService { public Task<bool> ConfirmAsync(string title, string message) => Task.FromResult(false); }
}
