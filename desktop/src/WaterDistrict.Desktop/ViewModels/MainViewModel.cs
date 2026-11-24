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
    public MainViewModel(IDesktopSessionClient sessions,IWorkflowClient? workflows=null)
    {
        this.sessions=sessions;
        if(workflows is not null)
        {
            Workflows=new(workflows);
            Workflows.SessionLost+=HandleFailure;
            Workflows.TicketCreated+=()=>Section="Tickets";
        }
    }
    [ObservableProperty,NotifyPropertyChangedFor(nameof(IsOverview)),NotifyPropertyChangedFor(nameof(IsConcerns)),NotifyPropertyChangedFor(nameof(IsTickets))]
    private string section="Overview";
    public bool IsOverview=>Section=="Overview" && !ShowDirectory;
    public bool IsConcerns=>Section=="Concerns" && !ShowDirectory;
    public bool IsTickets=>Section=="Tickets" && !ShowDirectory;

    [ObservableProperty] private string email = "";
    [ObservableProperty] private string password = "";
    [ObservableProperty, NotifyPropertyChangedFor(nameof(HasMessage))] private string message = "";
    [ObservableProperty, NotifyCanExecuteChangedFor(nameof(SignInCommand)), NotifyCanExecuteChangedFor(nameof(SignOutCommand)),
        NotifyCanExecuteChangedFor(nameof(RefreshAccessCommand)), NotifyCanExecuteChangedFor(nameof(LoadStaffCommand))]
    private bool isBusy;
    [ObservableProperty, NotifyPropertyChangedFor(nameof(IsSignedOut)), NotifyPropertyChangedFor(nameof(DisplayName)),
        NotifyPropertyChangedFor(nameof(RoleLabel)), NotifyPropertyChangedFor(nameof(IsAdmin))]
    private bool isSignedIn;
    [ObservableProperty,NotifyPropertyChangedFor(nameof(IsOverview)),NotifyPropertyChangedFor(nameof(IsConcerns)),NotifyPropertyChangedFor(nameof(IsTickets))] private bool showDirectory;
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
        }
        catch (SessionClientException exception) { Message = exception.Message; }
        finally { Password = ""; IsBusy = false; }
    }

    [RelayCommand(CanExecute = nameof(CanWork))]
    private async Task SignOutAsync()
    {
        if(Workflows?.IsBusy==true)return;
        IsBusy = true;
        ClearWorkspace();
        Message = "Signed out.";
        try { await sessions.SignOutAsync(); }
        finally { IsBusy = false; }
    }

    [RelayCommand(CanExecute = nameof(CanWork))]
    private async Task RefreshAccessAsync()
    {
        IsBusy = true;
        try
        {
            var previousRole=profile?.Role;
            profile = await sessions.RefreshProfileAsync();
            if(previousRole!=profile.Role) { Workflows?.Clear();Section="Overview"; }
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
        if (!IsAdmin || Workflows?.IsBusy==true) return;
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

    [RelayCommand] private void Overview() { if(Workflows?.IsBusy==true)return;ShowDirectory=false;Section="Overview";Message=""; }
    [RelayCommand] private async Task OpenConcernsAsync()
    {
        if(Workflows is null || Workflows.IsBusy)return;
        ShowDirectory=false;Section="Concerns";Message="";
        await Workflows.LoadConcernsCommand.ExecuteAsync(null);
    }
    [RelayCommand] private async Task OpenTicketsAsync()
    {
        if(Workflows is null || Workflows.IsBusy)return;
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
        Workflows?.Clear();
        Section="Overview";
        IsSignedIn = false;
        ShowDirectory = false;
        Staff.Clear();
        Password = "";
    }
}
