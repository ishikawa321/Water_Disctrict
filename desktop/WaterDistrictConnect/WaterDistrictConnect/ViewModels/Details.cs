using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;
namespace WaterDistrictConnect.ViewModels;
public partial class ConcernDetailViewModel : ViewModelBase
{
    private readonly WaterService service; private readonly Guid id; private readonly Action back; private readonly IConfirmationService confirmation;
    public bool IsOffice { get; } public bool CanRespond { get; }
    public Selection<ConcernCategory>[] Categories { get; } = ConcernSelections.Categories;
    public Selection<ConcernAction>[] Actions { get; } = [new("Mark under review", ConcernAction.Review), new("Customer-visible response", ConcernAction.Respond), new("Internal note (office only)", ConcernAction.InternalNote), new("Correct classification", ConcernAction.Reclassify), new("Resolve nontechnical concern", ConcernAction.Resolve), new("Close resolved concern", ConcernAction.Close), new("Reopen with reason", ConcernAction.Reopen)];
    [ObservableProperty] private ConcernDetail? detail;
    [ObservableProperty] private string response = "";
    [ObservableProperty] private string responseError = "";
    [ObservableProperty] private Selection<ConcernAction>? action;
    [ObservableProperty] private Selection<ConcernCategory>? category;
    public bool IsReclassify => Action?.Value == ConcernAction.Reclassify;
    public bool IsInternal => Action?.Value is ConcernAction.InternalNote or ConcernAction.Reclassify or ConcernAction.Review;
    public bool IsCustomerResponse => Action?.Value == ConcernAction.Respond;
    public bool IsNote => Action?.Value == ConcernAction.InternalNote;
    public bool CanWriteResponse => AvailableActions.Any(x => x.Value == ConcernAction.Respond);
    public bool CanWriteInternalNote => AvailableActions.Any(x => x.Value == ConcernAction.InternalNote);
    public string EditorHint => IsInternal ? "Write an internal note or reason (staff only)..." : "Type a customer-visible response or reason...";
    public string Attribution => Detail == null ? "" : $"Source: {Detail.Channel} · Recorded by: {Detail.RecordedBy}";
    public string EditorHeading => Action?.Value == ConcernAction.Respond ? "Customer response" : Action?.Value == ConcernAction.InternalNote ? "Internal note (staff only)" : "Office action and reason";
    public string SaveLabel => Action?.Value == ConcernAction.Respond ? "Send response" : Action?.Value == ConcernAction.InternalNote ? "Save internal note" : "Save office action";
    public TimelineRow? LatestReply => Detail?.Timeline.LastOrDefault(x => x.Kind == "Human response");
    public bool HasReply => LatestReply != null;
    public string Title => IsOffice && Detail != null ? "Concern " + Detail.Row.Reference : "Concern Details";
    partial void OnActionChanged(Selection<ConcernAction>? value)
    {
        OnPropertyChanged(nameof(IsReclassify)); OnPropertyChanged(nameof(IsInternal)); OnPropertyChanged(nameof(EditorHeading)); OnPropertyChanged(nameof(SaveLabel));
        OnPropertyChanged(nameof(IsCustomerResponse)); OnPropertyChanged(nameof(IsNote)); OnPropertyChanged(nameof(EditorHint));
    }
    public string ResponseTime => Detail?.FirstResponse is DateTimeOffset at ? TimeDisplay.Format(at) : "No human response recorded yet";
    [ObservableProperty] private Selection<ConcernAction>[] availableActions = [];
    partial void OnAvailableActionsChanged(Selection<ConcernAction>[] value) { OnPropertyChanged(nameof(CanWriteResponse)); OnPropertyChanged(nameof(CanWriteInternalNote)); }
    partial void OnDetailChanged(ConcernDetail? value)
    {
        Selection<ConcernAction>[] choices = value == null ? [] : Actions.Where(x => ConcernPolicy.Permitted(
            new ServiceConcern { State = value.Row.State, Category = value.Row.Category }, x.Value!.Value)).ToArray();
        if (!choices.SequenceEqual(AvailableActions)) AvailableActions = choices;
        OnPropertyChanged(nameof(ResponseTime));
        OnPropertyChanged(nameof(LatestReply)); OnPropertyChanged(nameof(HasReply)); OnPropertyChanged(nameof(Title));
        OnPropertyChanged(nameof(Attribution));
        if (!AvailableActions.Contains(Action)) Action = AvailableActions.FirstOrDefault();
        OnPropertyChanged(nameof(Action));
    }
    public ConcernDetailViewModel(WaterService service, Identity who, Guid id, IConfirmationService confirmation, Action back) { this.service = service; this.id = id; this.confirmation = confirmation; this.back = back; IsOffice = !who.IsClient; CanRespond = who.Has(Permissions.Respond); Action = Actions[1]; _ = RefreshAsync(); }
    private async Task Load() { Detail = await service.ConcernAsync(id); Category = Categories.Single(x => x.Value == Detail.Row.Category); }
    [RelayCommand] private Task RefreshAsync() => RunAsync(Load);
    [RelayCommand] private Task RespondAsync() => RunAsync(async () => {
        ResponseError = Response.Trim().Length < 10 || Response.Trim().Length > 4000 ? "Enter a meaningful response or reason (10–4000 characters)." : "";
        if (ResponseError != "") throw new BusinessException("Review the response or reason field.");
        if (Detail == null || Action?.Value == null) throw new BusinessException("Reload the concern and select an office action.");
        var action = Action.Value.Value;
        if (action is ConcernAction.Close or ConcernAction.Reopen && !await confirmation.ConfirmAsync($"{action} concern", $"{Detail.Row.Reference}\nCurrent status: {Detail.Row.StateLabel}\nResult: {(action == ConcernAction.Close ? "Closed" : "Under Review")}\nReason: {Response}")) return;
        await service.ProcessConcernAsync(id, Detail.Row.Version, action, Response, IsReclassify ? Category!.Value!.Value : Detail.Row.Category);
        Response = ""; await Load(); Success = "Concern update and history saved together.";
    });
    [RelayCommand] private void Back() => back();
    [RelayCommand] private void CustomerResponse() { if (AvailableActions.Contains(Actions[1])) Action = Actions[1]; }
    [RelayCommand] private void InternalNote() { if (AvailableActions.Contains(Actions[2])) Action = Actions[2]; }
}
public partial class TicketDetailViewModel : ViewModelBase
{
    private readonly WaterService service; private readonly Guid id; private readonly IConfirmationService confirmation; private readonly Action<Guid> openConcern; private readonly Action back;
    public bool CanRepair { get; }
    public TicketAction[] Actions { get; } = Enum.GetValues<TicketAction>();
    [ObservableProperty] private TicketDetail? detail;
    [ObservableProperty] private PlumberResource[] plumbers = [];
    [ObservableProperty] private PlumberResource? plumber;
    [ObservableProperty] private TicketAction action;
    [ObservableProperty] private string update = "";
    [ObservableProperty] private bool internalNote;
    public string AssignmentTime => Detail?.FirstAssigned is DateTimeOffset at ? TimeDisplay.Format(at) : "Not yet assigned";
    public bool IsAssign => Action == TicketAction.Assign;
    public bool CanInternal => Action == TicketAction.Progress;
    partial void OnActionChanged(TicketAction value) { OnPropertyChanged(nameof(IsAssign)); OnPropertyChanged(nameof(CanInternal)); InternalNote = false; }
    partial void OnDetailChanged(TicketDetail? value) => OnPropertyChanged(nameof(AssignmentTime));
    public TicketDetailViewModel(WaterService service, Identity who, Guid id, IConfirmationService confirmation, Action<Guid> openConcern, Action back) { this.service = service; this.id = id; this.confirmation = confirmation; this.openConcern = openConcern; this.back = back; CanRepair = who.Has(Permissions.Repair); _ = RefreshAsync(); }
    private async Task Load() { Detail = await service.TicketAsync(id); if (CanRepair) Plumbers = await service.PlumbersAsync(); }
    [RelayCommand] private Task RefreshAsync() => RunAsync(Load);
    [RelayCommand] private Task ApplyAsync() => RunAsync(async () => {
        if (Detail == null) return;
        if (Action is TicketAction.Close or TicketAction.Reopen && !await confirmation.ConfirmAsync($"{Action} repair ticket", $"{Detail.Row.Reference}\nCurrent state: {Detail.Row.StateLabel}\nIntended result: {(Action == TicketAction.Close ? "Closed, with signed Job Order reference" : "Reopened to Assigned (or Unassigned if no resource)")}\nReference / reason: {Update}")) return;
        await service.UpdateTicketAsync(id, Detail.Row.Version, Action, Update, Plumber?.Id, InternalNote); Update = ""; await Load(); Success = "Ticket and event history saved together.";
    });
    [RelayCommand] private void Concern() { if (Detail != null) openConcern(Detail.ConcernId); }
    [RelayCommand] private void Back() => back();
}
public partial class AccountsViewModel : ViewModelBase
{
    private readonly WaterService service; private readonly Action<Guid> concern; private readonly Action<Guid> ticket;
    private readonly Action? submit; private readonly Action? logout;
    public bool CanSubmit => submit != null;
    public bool CanLogout => logout != null;
    public bool IsOffice { get; } public string Title => IsOffice ? "Customer Accounts" : "My Account"; public string Username { get; }
    public bool ShowRelated { get; }
    public bool Empty => Accounts.Length == 0;
    partial void OnAccountsChanged(CustomerAccount[] value) => OnPropertyChanged(nameof(Empty));
    [ObservableProperty] private string search = "";
    [ObservableProperty] private CustomerAccount[] accounts = [];
    [ObservableProperty] private CustomerAccount? account;
    [ObservableProperty] private ConcernRow[] concerns = [];
    [ObservableProperty] private TicketRow[] tickets = [];
    [ObservableProperty] private ResourceRow[] resources = [];
    public AccountsViewModel(WaterService service, Identity who, Action<Guid> concern, Action<Guid> ticket, bool showRelated = true, Action? submit = null, Action? logout = null) { this.service = service; this.concern = concern; this.ticket = ticket; this.submit = submit; this.logout = logout; IsOffice = !who.IsClient; Username = who.Username; ShowRelated = showRelated; _ = RefreshAsync(); }
    partial void OnAccountChanged(CustomerAccount? value) { if (value != null && ShowRelated) _ = RelatedAsync(); }
    [RelayCommand] private Task RefreshAsync() => RunAsync(async () => { Accounts = await service.AccountsAsync(Search); if (IsOffice) Resources = (await service.PlumbersAsync()).Select(ResourceRow.From).ToArray(); if (Accounts.Length > 0) { Account = Accounts[0]; await LoadRelated(); } else { Account = null; Concerns = []; Tickets = []; } });
    private async Task LoadRelated() { if (Account == null || !ShowRelated) return; var id = Account.Id; var c = await service.ConcernsAsync(accountId: id); var t = await service.TicketsAsync(accountId: id); if (Account?.Id == id) { Concerns = c.Items; Tickets = t.Items; } }
    [RelayCommand] private Task RelatedAsync() => RunAsync(LoadRelated);
    [RelayCommand] private void OpenConcern(ConcernRow row) => concern(row.Id);
    [RelayCommand] private void OpenTicket(TicketRow row) => ticket(row.Id);
    [RelayCommand] private void Submit() => submit?.Invoke();
    [RelayCommand] private void SignOut() => logout?.Invoke();
}
public record ResourceRow(string Name, bool Available, string AvailabilityNote)
{
    public string AvailabilityLabel => Available ? "Available" : "Unavailable";
    public static ResourceRow From(PlumberResource resource) => new(resource.Name, resource.Available, resource.AvailabilityNote);
}
public partial class PlumbersViewModel : ViewModelBase
{
    private readonly WaterService service;
    [ObservableProperty] private ResourceRow[] plumbers = [];
    public bool Empty => Plumbers.Length == 0;
    partial void OnPlumbersChanged(ResourceRow[] value) => OnPropertyChanged(nameof(Empty));
    public PlumbersViewModel(WaterService service) { this.service = service; _ = RefreshAsync(); }
    [RelayCommand] private Task RefreshAsync() => RunAsync(async () => Plumbers = (await service.PlumbersAsync()).Select(ResourceRow.From).ToArray());
}
