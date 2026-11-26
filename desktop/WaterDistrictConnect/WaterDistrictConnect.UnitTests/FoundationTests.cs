using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;
using WaterDistrictConnect.Core.Persistence;
using WaterDistrictConnect.ViewModels;

namespace WaterDistrictConnect.UnitTests;

[Trait("Phase", "1")]
public class FoundationTests
{
    private sealed class NoDatabase : IDbContextFactory<WaterDbContext>
    { public WaterDbContext CreateDbContext() => throw new InvalidOperationException("No database should be accessed in this decision test."); }
    private sealed class NoConfirmation : IConfirmationService
    { public Task<bool> ConfirmAsync(string title, string message) => Task.FromResult(false); }
    private sealed class Feedback : ViewModelBase;
    private static Identity Client(Guid account) => new(Guid.NewGuid(), "demo", "Demo Client", [Permissions.Client], account, ["Client"]);

    [Fact] public void ClientOwnershipRejectsAnotherAccount()
    {
        var account = Guid.NewGuid(); var client = Client(account);
        Access.Account(client, account);
        Assert.Throws<BusinessException>(() => Access.Account(client, Guid.NewGuid()));
        Assert.Throws<BusinessException>(() => Access.Require(client, Permissions.ReadOffice));
    }
    [Theory] [InlineData(Permissions.Intake)] [InlineData(Permissions.Respond)] [InlineData(Permissions.Repair)]
    public void ReadOnlyOfficeRoleCannotMakeWorkflowDecisions(string permission)
    {
        var viewer = new Identity(Guid.NewGuid(), "viewer", "Viewer", [Permissions.ReadOffice], null, ["Office viewer"]);
        Access.Require(viewer, Permissions.ReadOffice);
        Assert.Throws<BusinessException>(() => Access.Require(viewer, permission));
    }
    [Fact] public void PasswordHashesAreSaltedAndRejectIncorrectPasswords()
    {
        var hasher = new PasswordHasher<User>(); var u = new User();
        var a = hasher.HashPassword(u, DemoSeeder.Password); var b = hasher.HashPassword(u, DemoSeeder.Password);
        Assert.NotEqual(a, b); Assert.DoesNotContain(DemoSeeder.Password, a);
        Assert.NotEqual(PasswordVerificationResult.Failed, hasher.VerifyHashedPassword(u, a, DemoSeeder.Password));
        Assert.Equal(PasswordVerificationResult.Failed, hasher.VerifyHashedPassword(u, a, "wrong-password"));
    }
    [Fact] public async Task InvalidLoginInputIsRejectedBeforeDatabaseAccess()
    {
        var session = new Session(); var auth = new AuthenticationService(new NoDatabase(), session);
        await Assert.ThrowsAsync<BusinessException>(() => auth.LoginAsync(" ", "password"));
        await Assert.ThrowsAsync<BusinessException>(() => auth.LoginAsync("admin", " "));
        Assert.Null(session.UserId);
    }
    [Fact] public async Task MissingConfigurationProducesActionableFeedbackAndRestoresBusyState()
    {
        var config = new AppConfiguration((string?)null); var factory = new ConfiguredContextFactory(config);
        var vm = new LoginViewModel(new(factory, new Session()), new(factory, config), false, _ => throw new Exception("Must not log in")) { Username = "admin", Password = "preserved input" };
        await vm.LoginCommand.ExecuteAsync(null);
        Assert.Contains("MWD_CONNECTION", vm.Error); Assert.Contains("not configured", vm.Error); Assert.False(vm.IsBusy); Assert.Equal("preserved input", vm.Password);
    }
    [Fact] public void MalformedConnectionStringDoesNotRevealItsContents()
    {
        var error = Assert.Throws<BusinessException>(() => new AppConfiguration("Password=SensitiveExample;not-a-key=value").Validate());
        Assert.Contains("configuration is invalid", error.Message); Assert.DoesNotContain("SensitiveExample", error.Message);
    }
    [Fact] public async Task BusyGuardBlocksDuplicateOperationsAndRecoversAfterFailure()
    {
        var vm = new Feedback(); var started = new TaskCompletionSource(); var release = new TaskCompletionSource(); int calls = 0;
        var operation = vm.RunAsync(async () => { calls++; started.SetResult(); await release.Task; throw new BusinessException("Recoverable failure"); });
        await started.Task; await vm.RunAsync(() => { calls++; return Task.CompletedTask; });
        Assert.True(vm.IsBusy); Assert.Equal(1, calls); release.SetResult(); await operation;
        Assert.False(vm.IsBusy); Assert.Equal("Recoverable failure", vm.Error);
    }
    [Fact] public void PhaseOneShellOnlyContainsImplementedFoundationDestinations()
    {
        var service = new WaterService(new NoDatabase(), new Session()); var who = Client(Guid.NewGuid());
        var shell = new WorkspaceViewModel(service, who, new NoConfirmation(), true, () => { });
        Assert.Equal(["overview", "accounts"], shell.Navigation.Select(x => x.Key));
        Assert.IsType<FoundationOverviewViewModel>(shell.Page);
        Assert.Throws<BusinessException>(() => shell.Navigate("submit"));
        Assert.Throws<BusinessException>(() => shell.OpenTicket(Guid.NewGuid()));
        shell.Navigate("accounts"); var accountPage = Assert.IsType<AccountsViewModel>(shell.Page); Assert.False(accountPage.ShowRelated);
    }
    [Fact] public void ShowPasswordSwitchPreservesPassword()
    {
        var f = new NoDatabase(); var vm = new LoginViewModel(new(f, new Session()), new(f, new AppConfiguration((string?)null)), true, _ => { }) { Password = "not-stored-password" };
        Assert.NotEqual('\0', vm.PasswordCharacter); vm.ShowPassword = true; Assert.Equal('\0', vm.PasswordCharacter); vm.ShowPassword = false;
        Assert.NotEqual('\0', vm.PasswordCharacter); Assert.Equal("not-stored-password", vm.Password);
    }
}
