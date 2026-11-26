using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;
namespace WaterDistrictConnect.ViewModels;
public partial class ConcernOverviewViewModel : ViewModelBase
{
    private readonly WaterService service; private readonly Action<string, string?> navigate; private readonly Action<Guid> open;
    public string Greeting { get; } public bool CanSubmit { get; } public bool IsClient { get; }
    public int MetricColumns => IsClient ? 2 : 3;
    public ConcernActivity? LatestActivity => Summary?.Activity?.FirstOrDefault();
    public bool HasActivity => LatestActivity != null;
    public bool NoPendingReview => Summary?.PendingReview?.Length == 0;
    [ObservableProperty] private ConcernOverview? summary;
    public bool Empty => Summary?.Total == 0;
    partial void OnSummaryChanged(ConcernOverview? value) { OnPropertyChanged(nameof(Empty)); OnPropertyChanged(nameof(LatestActivity)); OnPropertyChanged(nameof(HasActivity)); OnPropertyChanged(nameof(NoPendingReview)); }
    public ConcernOverviewViewModel(WaterService service, Identity who, Action<string, string?> navigate, Action<Guid> open) { this.service = service; this.navigate = navigate; this.open = open; IsClient = who.IsClient; Greeting = (IsClient ? "Welcome, " : "Hello, ") + who.Name + "!"; CanSubmit = who.IsClient || who.Has(Permissions.Intake); _ = RefreshAsync(); }
    [RelayCommand] private Task RefreshAsync() => RunAsync(async () => Summary = await service.ConcernOverviewAsync());
    [RelayCommand] private void Submit() => navigate("submit", null);
    [RelayCommand] private void Awaiting() => navigate("concerns", "Submitted");
    [RelayCommand] private void Open(ConcernRow row) => open(row.Id);
    [RelayCommand] private void All() => navigate("concerns", null);
    [RelayCommand] private void OpenLatest() { if (LatestActivity != null) open(LatestActivity.ConcernId); }
    [RelayCommand] private void OpenActivity(ConcernActivity activity) => open(activity.ConcernId);
}
