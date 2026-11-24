using System.Collections.ObjectModel;
using System.Net.Mail;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WaterDistrict.Application;

namespace WaterDistrict.Desktop.ViewModels;

public partial class MainViewModel(IDesktopSessionClient sessions) : ViewModelBase
{
    [ObservableProperty] private string email = "";
    [ObservableProperty] private string password = "";
    [ObservableProperty, NotifyPropertyChangedFor(nameof(HasMessage))] private string message = "";
    [ObservableProperty, NotifyCanExecuteChangedFor(nameof(SignInCommand)), NotifyCanExecuteChangedFor(nameof(SignOutCommand)),
        NotifyCanExecuteChangedFor(nameof(RefreshAccessCommand)), NotifyCanExecuteChangedFor(nameof(LoadStaffCommand))]
    private bool isBusy;
    [ObservableProperty, NotifyPropertyChangedFor(nameof(IsSignedOut)), NotifyPropertyChangedFor(nameof(DisplayName)),
        NotifyPropertyChangedFor(nameof(RoleLabel)), NotifyPropertyChangedFor(nameof(IsAdmin))]
    private bool isSignedIn;
    [ObservableProperty] private bool showDirectory;
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
        Message = "Signing in?";
        try
        {
            profile = await sessions.SignInAsync(Email.Trim(), Password);
            IsSignedIn = true;
            ShowDirectory = false;
            Message = "";
        }
        catch (SessionClientException exception) { Message = exception.Message; }
        finally { Password = ""; IsBusy = false; }
    }

    [RelayCommand(CanExecute = nameof(CanWork))]
    private async Task SignOutAsync()
    {
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
            profile = await sessions.RefreshProfileAsync();
            OnPropertyChanged(nameof(IsAdmin));
            OnPropertyChanged(nameof(DisplayName));
            OnPropertyChanged(nameof(RoleLabel));
            if (!IsAdmin) { ShowDirectory = false; Staff.Clear(); }
            Message = "Your access is up to date.";
        }
        catch (SessionClientException exception) { HandleFailure(exception); }
        finally { IsBusy = false; }
    }

    [RelayCommand(CanExecute = nameof(CanWork))]
    private async Task LoadStaffAsync()
    {
        if (!IsAdmin) return;
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

    [RelayCommand] private void Overview() { ShowDirectory = false; Message = ""; }
    private void HandleFailure(SessionClientException exception)
    {
        if (exception.RequiresSignIn) ClearWorkspace();
        Message = exception.Message;
    }
    private void ClearWorkspace()
    {
        profile = null;
        IsSignedIn = false;
        ShowDirectory = false;
        Staff.Clear();
        Password = "";
    }
}
