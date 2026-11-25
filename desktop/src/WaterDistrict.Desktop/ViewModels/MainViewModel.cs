using System.Collections.ObjectModel;
using System.Net.Mail;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WaterDistrict.Application;

namespace WaterDistrict.Desktop.ViewModels;

public partial class MainViewModel : ViewModelBase
{
    private readonly IDesktopSessionClient sessions;
    public WorkflowViewModel? Workflows { get; }
    public OfficeViewModel? Office { get; }
    public MainViewModel(IDesktopSessionClient sessions,IWorkflowClient? workflows=null,IOfficeClient? office=null)
    {
        this.sessions=sessions;
        if(office is not null){Office=new(office);Office.SessionLost+=HandleFailure;}
        if(workflows is not null)
        {
            Workflows=new(workflows);
            Workflows.SessionLost+=HandleFailure;
            Workflows.TicketCreated+=()=>Section="Tickets";
        }
    }
    [ObservableProperty,NotifyPropertyChangedFor(nameof(IsOverview)),NotifyPropertyChangedFor(nameof(IsConcerns)),NotifyPropertyChangedFor(nameof(IsTickets)),NotifyPropertyChangedFor(nameof(IsOffice))]
    private string section="Overview";
    public bool IsOverview=>Section=="Overview" && !ShowDirectory;
    public bool IsConcerns=>Section=="Concerns" && !ShowDirectory;
    public bool IsTickets=>Section=="Tickets" && !ShowDirectory;
    public bool IsOffice=>IsAdmin && !ShowDirectory && Section is "Accounts" or "Bills" or "Payments" or "Announcements";
    public bool IsAccounts => IsOffice && Section == "Accounts";
    public bool IsBills => IsOffice && Section == "Bills";
    public bool IsPayments => IsOffice && Section == "Payments";
    public bool IsAnnouncements => IsOffice && Section == "Announcements";
    public string WorkspaceTitle => ShowDirectory ? "Staff directory" : Section switch
    {
        "Overview" => "Dashboard", "Concerns" => "Service concerns", "Tickets" => "Repair tickets",
        "Accounts" => "Service accounts", "Bills" => "Billing records", "Payments" => "Verified payments",
        "Announcements" => "Announcements", _ => "Workspace"
    };

    // Navigation visuals follow the same state used to show the authorized page.
    partial void OnSectionChanged(string value) => NotifyNavigationChanged();
    partial void OnShowDirectoryChanged(bool value) => NotifyNavigationChanged();
    private void NotifyNavigationChanged()
    {
        OnPropertyChanged(nameof(IsAccounts));
        OnPropertyChanged(nameof(IsBills));
        OnPropertyChanged(nameof(IsPayments));
        OnPropertyChanged(nameof(IsAnnouncements));
        OnPropertyChanged(nameof(WorkspaceTitle));
    }

    [ObservableProperty] private string email = "";
    [ObservableProperty] private string password = "";
    [ObservableProperty, NotifyPropertyChangedFor(nameof(HasMessage))] private string message = "";
    [ObservableProperty, NotifyCanExecuteChangedFor(nameof(SignInCommand)), NotifyCanExecuteChangedFor(nameof(SignOutCommand)),
        NotifyCanExecuteChangedFor(nameof(RefreshAccessCommand)), NotifyCanExecuteChangedFor(nameof(LoadStaffCommand))]
    private bool isBusy;
    [ObservableProperty, NotifyPropertyChangedFor(nameof(IsSignedOut)), NotifyPropertyChangedFor(nameof(DisplayName)),
        NotifyPropertyChangedFor(nameof(RoleLabel)), NotifyPropertyChangedFor(nameof(IsAdmin))]
    private bool isSignedIn;
    [ObservableProperty,NotifyPropertyChangedFor(nameof(IsOverview)),NotifyPropertyChangedFor(nameof(IsConcerns)),NotifyPropertyChangedFor(nameof(IsTickets)),NotifyPropertyChangedFor(nameof(IsOffice))] private bool showDirectory;
    private SessionProfile? profile;
    public ObservableCollection<StaffMember> Staff { get; } = [];
    public bool HasMessage => !string.IsNullOrWhiteSpace(Message);
    public bool IsSignedOut => !IsSignedIn;
    public string DisplayName => string.IsNullOrWhiteSpace(profile?.DisplayName) ? "Office personnel" : profile.DisplayName;
    public string RoleLabel => profile?.Role == "admin" ? "Administrator" : "Staff";
    public bool IsAdmin => IsSignedIn && profile?.Role == "admin";
    private bool CanWork() => !IsBusy;

    [RelayCommand(CanExecute = nameof(CanWork))]
    private async Task SignInAsync()
    {
        if (!MailAddress.TryCreate(Email.Trim(), out var address) || address.Address != Email.Trim() || string.IsNullOrEmpty(Password))
        { Message = "Enter a valid email address and your password."; return; }
        IsBusy = true;
        Message = "Signing in...";
        try
        {
            profile = await sessions.SignInAsync(Email.Trim(), Password);
            IsSignedIn = true;
            ShowDirectory = false;
            Section="Overview";
            if(Workflows is not null) Workflows.IsAdmin=profile.Role=="admin";
            Message = "";
            if(IsAdmin && Office is not null)await Office.LoadSummaryCommand.ExecuteAsync(null);
        }
        catch (SessionClientException exception) { Message = exception.Message; }
        finally { Password = ""; IsBusy = false; }
    }

    [RelayCommand(CanExecute = nameof(CanWork))]
    private async Task SignOutAsync()
    {
        if((Workflows?.IsBusy==true || Office?.IsBusy==true))return;
        IsBusy = true;
        ClearWorkspace();
        Message = "Signed out.";
        try { await sessions.SignOutAsync(); }
        finally { IsBusy = false; }
    }

    [RelayCommand(CanExecute = nameof(CanWork))]
    private async Task RefreshAccessAsync()
    {
        if(Workflows?.IsBusy==true || Office?.IsBusy==true)return;
        IsBusy = true;
        try
        {
            var previousRole=profile?.Role;
            profile = await sessions.RefreshProfileAsync();
            if(previousRole!=profile.Role) { Workflows?.Clear();Office?.Clear();Section="Overview"; }
            OnPropertyChanged(nameof(IsAdmin));
            OnPropertyChanged(nameof(DisplayName));
            OnPropertyChanged(nameof(RoleLabel));
            if (!IsAdmin) { ShowDirectory = false; Staff.Clear(); }
            if(Workflows is not null) Workflows.IsAdmin=IsAdmin;
            Message = "Your access is up to date.";
        }
        catch (SessionClientException exception) { HandleFailure(exception); }
        finally { IsBusy = false; }
    }

    [RelayCommand(CanExecute = nameof(CanWork))]
    private async Task LoadStaffAsync()
    {
        if (!IsAdmin || (Workflows?.IsBusy==true || Office?.IsBusy==true)) return;
        IsBusy = true;
        try
        {
            var members = await sessions.GetStaffAsync();
            Staff.Clear();
            foreach (var member in members) Staff.Add(member);
            ShowDirectory = true;
            Message = members.Count == 0 ? "No active office profiles are visible. Check profile access with your administrator." : "";
        }
        catch (SessionClientException exception) { HandleFailure(exception); }
        finally { IsBusy = false; }
    }

    [RelayCommand] private async Task OpenOfficeAsync(string page)
    {
        if(page is not ("Accounts" or "Bills" or "Payments" or "Announcements"))return;
        if(!IsAdmin || Office is null || (Workflows?.IsBusy==true || Office.IsBusy))return;
        ShowDirectory=false;Section=page;Message="";await Office.OpenAsync(page);
    }
    [RelayCommand] private void Overview() { if((Workflows?.IsBusy==true || Office?.IsBusy==true))return;ShowDirectory=false;Section="Overview";Message=""; }
    [RelayCommand] private async Task OpenConcernsAsync()
    {
        if(Workflows is null || Workflows.IsBusy || Office?.IsBusy==true)return;
        ShowDirectory=false;Section="Concerns";Message="";
        await Workflows.LoadConcernsCommand.ExecuteAsync(null);
    }
    [RelayCommand] private async Task OpenTicketsAsync()
    {
        if(Workflows is null || Workflows.IsBusy || Office?.IsBusy==true)return;
        ShowDirectory=false;Section="Tickets";Message="";
        await Workflows.LoadTicketsCommand.ExecuteAsync(null);
    }
    private void HandleFailure(SessionClientException exception)
    {
        if (exception.RequiresSignIn) ClearWorkspace();
        Message = exception.Message;
    }
    private void ClearWorkspace()
    {
        profile = null;
        Workflows?.Clear();Office?.Clear();
        Section="Overview";
        IsSignedIn = false;
        ShowDirectory = false;
        Staff.Clear();
        Password = "";
    }
}
