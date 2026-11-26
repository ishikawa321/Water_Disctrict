using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Persistence;
using WaterDistrictConnect.Core.Domain;

namespace WaterDistrictConnect.ViewModels;
public partial class RootViewModel : ObservableObject
{
    private readonly AuthenticationService auth; private readonly WaterService service; private readonly DatabaseSetup setup; private readonly Session session; private readonly IConfirmationService confirmation; private readonly AppConfiguration configuration;
    [ObservableProperty] private ViewModelBase current = null!;
    public RootViewModel(AuthenticationService auth, WaterService service, DatabaseSetup setup, Session session, IConfirmationService confirmation, AppConfiguration configuration)
    { this.auth = auth; this.service = service; this.setup = setup; this.session = session; this.confirmation = confirmation; this.configuration = configuration; ShowLogin(); }
    private void ShowLogin() => Current = new LoginViewModel(auth, setup, configuration.DemoMode, identity => { Current = new WorkspaceViewModel(service, identity, confirmation, configuration.DemoMode, Logout, foundationOnly: false); });
    private void Logout() { session.Clear(); ShowLogin(); }
}
public partial class LoginViewModel(AuthenticationService auth, DatabaseSetup setup, bool demoMode, Action<Identity> loggedIn) : ViewModelBase
{
    [ObservableProperty] private string username = "";
    [ObservableProperty] private string password = "";
    [ObservableProperty] private bool showPassword;
    public bool DemoMode => demoMode;
    public char PasswordCharacter => ShowPassword ? '\0' : '●';
    partial void OnShowPasswordChanged(bool value) => OnPropertyChanged(nameof(PasswordCharacter));
    [RelayCommand] private Task LoginAsync() => RunAsync(async () => {
        InputRules.Required(Username, "Username", 64); InputRules.Required(Password, "Password", 500);
        await setup.CheckAsync(); var who = await auth.LoginAsync(Username, Password); Password = ""; loggedIn(who);
    });
}
public record NavigationItem(string Label, string Key, string Icon);
public partial class WorkspaceViewModel : ViewModelBase
{
    private readonly WaterService service; private readonly IConfirmationService confirmation; private readonly Action logout;
    public Identity Who { get; } public bool DemoMode { get; } public string UserLabel => Who.Name + " · " + Who.RoleLabel;
    public string Initials => string.Concat(Who.Name.Split(' ', StringSplitOptions.RemoveEmptyEntries).Take(2).Select(x => x[0])).ToUpperInvariant();
    public bool FoundationOnly { get; }
    public NavigationItem[] Navigation { get; }
    [ObservableProperty] private NavigationItem? selectedNavigation;
    [ObservableProperty] private ViewModelBase page = null!;
    private bool synchronizingNavigation;
    public WorkspaceViewModel(WaterService service, Identity who, IConfirmationService confirmation, bool demoMode, Action logout, bool foundationOnly = true)
    {
        this.service = service; Who = who; this.confirmation = confirmation; DemoMode = demoMode; this.logout = logout; FoundationOnly = foundationOnly;
        Navigation = who.IsClient ? [new("Overview", "overview", "M3,10 L12,3 21,10 M5,9 V21 H19 V9 M9,21 V14 H15 V21"), new("Submit Concern", "submit", "M12,4 V20 M4,12 H20"), new("My Concerns", "concerns", "M4,4 H20 V17 H9 L4,21 Z M8,8 H16 M8,12 H16"), new("My Repair Tickets", "tickets", "M4,4 H20 V21 H4 Z M8,9 H16 M8,14 H16"), new("My Account", "accounts", "M12,3 A4,4 0 1 1 12,11 A4,4 0 1 1 12,3 M4,21 V18 C4,12 20,12 20,18 V21")]
          : [new("Overview", "overview", "M3,10 L12,3 21,10 M5,9 V21 H19 V9 M9,21 V14 H15 V21"), new("Concern Queue", "concerns", "M4,4 H20 V17 H9 L4,21 Z M8,8 H16 M8,12 H16"), new("Repair Tickets", "tickets", "M4,4 H20 V21 H4 Z M8,9 H16 M8,14 H16"), new("Customer Accounts", "accounts", "M12,3 A4,4 0 1 1 12,11 A4,4 0 1 1 12,3 M4,21 V18 C4,12 20,12 20,18 V21"), new("Plumber Resources", "plumbers", "M4,8 H20 V21 H4 Z M8,8 V3 H16 V8 M4,13 H20")];
        Navigation = Navigation.Where(x => x.Key != "tickets").ToArray();
        if (FoundationOnly) Navigation = Navigation.Where(x => x.Key is "overview" or "accounts" or "plumbers").ToArray();
        if (who.IsClient || WaterService.CanManageBilling(who))
            Navigation = [.. Navigation, new(who.IsClient ? "My Bills" : "Billing", "billing", "M4,3 H20 V21 H4 Z M8,7 H16 M8,12 H16 M8,17 H13")];
        SelectedNavigation = Navigation[0];
    }
    partial void OnSelectedNavigationChanged(NavigationItem? value) { if (value != null && !synchronizingNavigation) Navigate(value.Key); }
    private void SelectSection(string key)
    {
        var item = Navigation.FirstOrDefault(x => x.Key == key);
        if (item == null || item == SelectedNavigation) return;
        synchronizingNavigation = true;
        try { SelectedNavigation = item; }
        finally { synchronizingNavigation = false; }
    }
    public void Navigate(string key, string? filter = null)
    {
        if (key == "tickets") throw new BusinessException("Repair processing starts in Phase 3.");
        if (key == "submit" && !Who.IsClient && !Who.Has(Permissions.Intake)) throw new BusinessException("You do not have intake permission.");
        if (FoundationOnly && !Navigation.Any(x => x.Key == key)) throw new BusinessException("This destination is outside the Phase 1 foundation.");
        SelectSection(key == "submit" && !Who.IsClient ? "concerns" : key);
        Page = key switch {
            "billing" => new BillingViewModel(service, Who),
            "submit" => new SubmitViewModel(service, Who, OpenConcern),
            "concerns" => new ConcernsViewModel(service, Who, OpenConcern, () => Navigate("submit"), filter),
            "tickets" => new TicketsViewModel(service, Who, OpenTicket, filter),
            "accounts" => new AccountsViewModel(service, Who, OpenConcern, OpenTicket, showRelated: false,
                submit: Who.IsClient && !FoundationOnly ? () => Navigate("submit") : null, logout: logout),
            "plumbers" => new PlumbersViewModel(service),
            _ => FoundationOnly ? new FoundationOverviewViewModel(service, Who, () => Navigate("accounts")) : new ConcernOverviewViewModel(service, Who, Navigate, OpenConcern)
        };
    }
    public void OpenConcern(Guid id) { if (FoundationOnly) throw new BusinessException("Concern processing starts in Phase 2."); SelectSection("concerns"); Page = new ConcernDetailViewModel(service, Who, id, confirmation, () => Navigate("concerns")); }
    public void OpenTicket(Guid id) => throw new BusinessException("Repair processing starts in Phase 3.");
    [RelayCommand] private void Logout() => logout();
}
