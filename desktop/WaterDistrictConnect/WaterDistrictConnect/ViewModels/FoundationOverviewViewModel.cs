using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;

namespace WaterDistrictConnect.ViewModels;

public partial class FoundationOverviewViewModel : ViewModelBase
{
    private readonly WaterService service;
    private readonly Action accounts;
    public Identity Who { get; }
    public bool IsOffice => !Who.IsClient;
    public string Greeting => "Welcome, " + Who.Name;
    public string Experience => Who.IsClient ? "CLIENT WORKSPACE" : "OFFICE WORKSPACE";
    public string[] AccessLabels => Who.Permissions.Select(p => p switch
    {
        Permissions.ReadOffice => "Read office reference accounts and plumber resources",
        Permissions.Intake => "Concern intake privilege",
        Permissions.Respond => "Concern response privilege",
        Permissions.Repair => "Ticket coordination privilege",
        Permissions.Client => "Read only your linked customer account",
        _ => "Assigned application privilege"
    }).ToArray();
    [ObservableProperty] private string accountSummary = "Loading saved reference data…";
    [ObservableProperty] private string resourceSummary = "Loading saved reference data…";
    public FoundationOverviewViewModel(WaterService service, Identity who, Action accounts)
    { this.service = service; Who = who; this.accounts = accounts; _ = RefreshAsync(); }
    [RelayCommand] private Task RefreshAsync() => RunAsync(async () =>
    {
        var saved = await service.AccountsAsync();
        AccountSummary = Who.IsClient ? saved.SingleOrDefault()?.ToString() ?? "No linked account available. Contact the demo administrator." : $"{saved.Length} saved fictional customer accounts";
        if (IsOffice) ResourceSummary = $"{(await service.PlumbersAsync()).Length} saved fictional plumber resources";
    });
    [RelayCommand] private void Accounts() => accounts();
}
