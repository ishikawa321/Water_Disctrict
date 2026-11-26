using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;

namespace WaterDistrictConnect.ViewModels;
public partial class OverviewViewModel : ViewModelBase
{
    private readonly WaterService service; private readonly Action<string,string?> navigate; private readonly Action<Guid> open;
    public string Greeting { get; } public bool IsClient { get; }
    [ObservableProperty] private Overview? summary;
    public OverviewViewModel(WaterService service, Identity who, Action<string,string?> navigate, Action<Guid> open) { this.service = service; this.navigate = navigate; this.open = open; Greeting = "Welcome, " + who.Name; IsClient = who.IsClient; _ = RefreshAsync(); }
    [RelayCommand] private Task RefreshAsync() => RunAsync(async () => Summary = await service.OverviewAsync());
    [RelayCommand] private void Submit() => navigate("submit", null);
    [RelayCommand] private void Awaiting() => navigate("concerns", "Received");
    [RelayCommand] private void Unassigned() => navigate("tickets", "Unassigned");
    [RelayCommand] private void Active() => navigate("tickets", "InProgress");
    [RelayCommand] private void Open(ConcernRow row) => open(row.Id);
}
public partial class SubmitViewModel : ViewModelBase
{
    private readonly WaterService service; private readonly Identity who; private readonly Action<Guid> open;
    private readonly Guid submissionKey = Guid.NewGuid();
    public bool IsOffice => !who.IsClient; public bool CanSubmit => who.IsClient || who.Has(Permissions.Intake);
    public Selection<ConcernCategory>[] Categories { get; } = ConcernSelections.Categories;
    public string[] Channels { get; } = ["Telephone", "Walk-in", "Other"];
    [ObservableProperty] private CustomerAccount[] accounts = [];
    [ObservableProperty] private CustomerAccount? account;
    [ObservableProperty] private string accountSearch = "";
    [ObservableProperty] private Selection<ConcernCategory>? category;
    [ObservableProperty] private string subject = "";
    [ObservableProperty] private string description = "";
    [ObservableProperty] private string location = "";
    [ObservableProperty] private string contact = "";
    [ObservableProperty] private string channel = "Telephone";
    [ObservableProperty] private string subjectError = "";
    [ObservableProperty] private string descriptionError = "";
    [ObservableProperty] private string locationError = "";
    [ObservableProperty] private string accountError = "";
    [ObservableProperty] private string categoryError = "";
    [ObservableProperty] private string contactError = "";
    [ObservableProperty] private Guid? savedId;
    [ObservableProperty] private bool isReviewing;
    public bool NotSaved => SavedId == null;
    public bool IsEditing => NotSaved && !IsReviewing;
    partial void OnSavedIdChanged(Guid? value) { OnPropertyChanged(nameof(NotSaved)); OnPropertyChanged(nameof(IsEditing)); }
    partial void OnIsReviewingChanged(bool value) => OnPropertyChanged(nameof(IsEditing));
    partial void OnAccountChanged(CustomerAccount? value) { if (value != null) Location = value.Address; }
    public SubmitViewModel(WaterService service, Identity who, Action<Guid> open) { this.service = service; this.who = who; this.open = open; _ = LoadAsync(); }
    [RelayCommand] private Task LoadAsync() => RunAsync(async () => { Accounts = await service.AccountsAsync(IsOffice ? AccountSearch : ""); if (who.IsClient) Account = Accounts.SingleOrDefault(); else if (Account != null && !Accounts.Any(x => x.Id == Account.Id)) Account = null; });
    private void Validate()
    {
        SubjectError = string.IsNullOrWhiteSpace(Subject) ? "Enter a subject." : Subject.Length > 160 ? "Use at most 160 characters." : "";
        DescriptionError = string.IsNullOrWhiteSpace(Description) ? "Describe the concern." : Description.Length > 4000 ? "Use at most 4000 characters." : "";
        LocationError = string.IsNullOrWhiteSpace(Location) ? "Enter the service location." : Location.Length > 300 ? "Use at most 300 characters." : "";
        AccountError = Account == null ? "Choose an eligible customer account, or retry account loading." : "";
        CategoryError = Category?.Value == null ? "Choose a category." : "";
        ContactError = Contact.Length > 200 ? "Use at most 200 characters." : "";
        if (SubjectError + DescriptionError + LocationError + AccountError + CategoryError + ContactError != "") throw new BusinessException("Review the highlighted fields.");
    }
    [RelayCommand] private Task ReviewAsync() => RunAsync(() => { Validate(); IsReviewing = true; return Task.CompletedTask; });
    [RelayCommand] private void Edit() => IsReviewing = false;
    [RelayCommand] private Task SubmitAsync() => RunAsync(async () => {
        if (SavedId.HasValue) return;
        Validate();
        var id = await service.SubmitAsync(new(Account!.Id, Category!.Value!.Value, Subject, Description, Location, Contact, Channel, submissionKey));
        SavedId = id; var detail = await service.ConcernAsync(id); Success = $"Saved {detail.Row.Reference}. Received — awaiting office review. This automatic receipt does not mean staff have responded.";
    });
    [RelayCommand] private void ViewSaved() { if (SavedId.HasValue) open(SavedId.Value); }
}
public partial class ConcernsViewModel : ViewModelBase
{
    private readonly WaterService service; private readonly Action<Guid> open; private readonly Action submit;
    public string Title { get; } public bool CanIntake { get; } public bool IsOffice { get; }
    public string Subtitle => IsOffice ? "All reported concerns from customers, for review and action." : "The concerns you've submitted and their current status.";
    public string SearchHint => IsOffice ? "Search reference, subject, or customer account..." : "Search your concerns by reference or subject...";
    public string RegisterLabel => IsOffice ? "+  Register Concern" : "Submit a concern";
    private bool ready;
    public Selection<ConcernCategory>[] Categories { get; } = [new("All categories", null), .. ConcernSelections.Categories];
    public Selection<ConcernState>[] States { get; } = [new("All statuses", null), .. ConcernSelections.States];
    [ObservableProperty] private string search = "";
    [ObservableProperty] private Selection<ConcernCategory>? category;
    [ObservableProperty] private Selection<ConcernState>? state;
    [ObservableProperty] private ConcernRow[] rows = [];
    [ObservableProperty] private string pageLabel = "";
    [ObservableProperty] private string rangeLabel = "";
    [ObservableProperty] private int pageNumber = 1;
    [ObservableProperty] private bool hasPrevious;
    [ObservableProperty] private bool hasNext;
    private int page = 1;
    public bool Empty => Rows.Length == 0 && !IsBusy && string.IsNullOrEmpty(Error);
    partial void OnRowsChanged(ConcernRow[] value) => OnPropertyChanged(nameof(Empty));
    partial void OnStateChanged(Selection<ConcernState>? value) { if (ready && !IsOffice && !IsBusy) _ = RefreshAsync(); }
    public ConcernsViewModel(WaterService service, Identity who, Action<Guid> open, Action submit, string? filter) { this.service = service; this.open = open; this.submit = submit; IsOffice = !who.IsClient; Title = who.IsClient ? "My Concerns" : "Concern Queue"; CanIntake = who.IsClient || who.Has(Permissions.Intake); Category = Categories[0]; State = States.FirstOrDefault(x => x.Value?.ToString() == filter) ?? States[0]; ready = true; _ = RefreshAsync(); }
    private async Task Load() { var result = await service.ConcernsAsync(Search, Category?.Value, State?.Value, page); Rows = result.Items; page = result.Number; PageNumber = page; HasPrevious = page > 1; HasNext = page * result.Size < result.Total; PageLabel = $"Page {page} of {Math.Max(1, (result.Total + result.Size - 1) / result.Size)}"; RangeLabel = result.Total == 0 ? "Showing 0 concerns" : $"Showing {(page - 1) * result.Size + 1}–{(page - 1) * result.Size + Rows.Length} of {result.Total} concerns"; }
    [RelayCommand] private Task RefreshAsync() => RunAsync(async () => { page = 1; await Load(); });
    [RelayCommand] private Task ClearAsync() => RunAsync(async () => { Search = ""; Category = Categories[0]; State = States[0]; page = 1; await Load(); });
    [RelayCommand] private Task NextAsync() => RunAsync(async () => { if (HasNext) { page++; await Load(); } });
    [RelayCommand] private Task PreviousAsync() => RunAsync(async () => { if (HasPrevious) { page--; await Load(); } });
    [RelayCommand] private void Open(ConcernRow row) => open(row.Id);
    [RelayCommand] private void Submit() => submit();
}
public partial class TicketsViewModel : ViewModelBase
{
    private readonly WaterService service; private readonly Action<Guid> open;
    public string Title { get; } public string[] States { get; } = ["All states", "Unassigned", "Assigned", "InProgress", "Resolved", "Closed"];
    [ObservableProperty] private string search = "";
    [ObservableProperty] private string state = "All states";
    [ObservableProperty] private TicketRow[] rows = [];
    [ObservableProperty] private string pageLabel = "";
    private int page = 1;
    public bool Empty => Rows.Length == 0;
    partial void OnRowsChanged(TicketRow[] value) => OnPropertyChanged(nameof(Empty));
    public TicketsViewModel(WaterService service, Identity who, Action<Guid> open, string? filter) { this.service = service; this.open = open; Title = who.IsClient ? "My Repair Tickets" : "Repair Tickets"; if (filter != null) State = filter; _ = RefreshAsync(); }
    private async Task Load() { var result = await service.TicketsAsync(Search, Enum.TryParse<TicketState>(State, out var s) ? s : null, page); Rows = result.Items; page = result.Number; PageLabel = $"Page {page} · {result.Total} tickets · 20 per page"; }
    [RelayCommand] private Task RefreshAsync() => RunAsync(async () => { page = 1; await Load(); });
    [RelayCommand] private Task NextAsync() => RunAsync(async () => { page++; await Load(); });
    [RelayCommand] private Task PreviousAsync() => RunAsync(async () => { page = Math.Max(1, page - 1); await Load(); });
    [RelayCommand] private void Open(TicketRow row) => open(row.Id);
}
