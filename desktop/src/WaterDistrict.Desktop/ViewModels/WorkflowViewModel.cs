using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WaterDistrict.Application;
using WaterDistrict.Domain;

namespace WaterDistrict.Desktop.ViewModels;

public partial class WorkflowViewModel(IWorkflowClient client) : ViewModelBase
{
    public event Action<SessionClientException>? SessionLost;
    public event Action? TicketCreated;
    private Guid requestId = Guid.NewGuid();
    private bool applyingTicket;
    public ObservableCollection<AccountOption> Accounts { get; } = [];
    public ObservableCollection<StaffMember> Assignees { get; } = [];
    public ObservableCollection<ConcernRecord> Concerns { get; } = [];
    public ObservableCollection<TicketRecord> Tickets { get; } = [];
    public ObservableCollection<HistoryRecord> History { get; } = [];
    public string[] Categories => WorkflowRules.Categories;
    public string[] ConcernFilters => ["All", ..WorkflowRules.ConcernStates];
    public string[] TicketFilters => ["All", ..WorkflowRules.TicketStates];
    public string[] ReviewStates => ["Under review","Closed"];
    [ObservableProperty] private bool isAdmin;
    [ObservableProperty, NotifyCanExecuteChangedFor(nameof(SaveConcernCommand)),NotifyCanExecuteChangedFor(nameof(SaveReviewCommand)),
        NotifyCanExecuteChangedFor(nameof(CreateRepairTicketCommand)),NotifyCanExecuteChangedFor(nameof(SaveTicketCommand)),
        NotifyCanExecuteChangedFor(nameof(LoadConcernsCommand)),NotifyCanExecuteChangedFor(nameof(LoadAccountsCommand)),
        NotifyCanExecuteChangedFor(nameof(LoadTicketsCommand)),NotifyCanExecuteChangedFor(nameof(LoadSelectedTicketCommand))]
    private bool isBusy;
    [ObservableProperty,NotifyPropertyChangedFor(nameof(HasMessage))] private string message="";
    [ObservableProperty] private bool showIntake;
    [ObservableProperty] private string accountSearch="";
    [ObservableProperty] private AccountOption? selectedAccount;
    [ObservableProperty] private string category="Water supply";
    [ObservableProperty] private string subject="";
    [ObservableProperty] private string description="";
    [ObservableProperty] private string concernSearch="";
    [ObservableProperty] private string concernFilter="All";
    [ObservableProperty,NotifyPropertyChangedFor(nameof(HasConcern)),NotifyPropertyChangedFor(nameof(CanReview)),NotifyPropertyChangedFor(nameof(CanDispatch)),
        NotifyCanExecuteChangedFor(nameof(SaveReviewCommand)),NotifyCanExecuteChangedFor(nameof(CreateRepairTicketCommand))]
    private ConcernRecord? selectedConcern;
    [ObservableProperty] private string reviewStatus="Under review";
    [ObservableProperty] private string reviewResponse="";
    [ObservableProperty] private string creationNote="";
    [ObservableProperty] private string ticketSearch="";
    [ObservableProperty] private string ticketFilter="All";
    [ObservableProperty,NotifyPropertyChangedFor(nameof(HasTicket)),NotifyPropertyChangedFor(nameof(NextTicketStates)),
        NotifyCanExecuteChangedFor(nameof(SaveTicketCommand)),NotifyCanExecuteChangedFor(nameof(LoadSelectedTicketCommand))]
    private TicketRecord? selectedTicket;
    [ObservableProperty,NotifyCanExecuteChangedFor(nameof(SaveTicketCommand))] private bool detailsLoaded;
    [ObservableProperty] private string ticketStatus="Open";
    [ObservableProperty] private StaffMember? selectedAssignee;
    [ObservableProperty] private string ticketNote="";
    public bool HasMessage => !string.IsNullOrWhiteSpace(Message);
    public bool HasConcern => SelectedConcern is not null;
    public bool HasTicket => SelectedTicket is not null;
    public bool CanReview => !IsBusy && SelectedConcern is { TicketId:null } row && row.Status is "Submitted" or "Under review";
    public bool CanDispatch => !IsBusy && IsAdmin && SelectedConcern is { Status:"Under review",TicketId:null };
    public bool CanEditTicket => !IsBusy && DetailsLoaded && SelectedTicket is not null && SelectedTicket.Status!="Resolved";
    public string[] NextTicketStates => SelectedTicket?.Status switch {
        "Open" => ["Open","Assigned"], "Assigned" => ["Assigned","In progress"],
        "In progress" => ["In progress","Resolved"], "Resolved" => ["Resolved"], _ => ["Open"] };
    private bool Available() => !IsBusy;
    private bool TicketAvailable() => !IsBusy && SelectedTicket is not null;
    partial void OnIsBusyChanged(bool value)
    { OnPropertyChanged(nameof(CanReview));OnPropertyChanged(nameof(CanDispatch));OnPropertyChanged(nameof(CanEditTicket)); }
    partial void OnIsAdminChanged(bool value)
    { OnPropertyChanged(nameof(CanDispatch)); CreateRepairTicketCommand.NotifyCanExecuteChanged(); if(!value) Assignees.Clear(); }
    partial void OnDetailsLoadedChanged(bool value) => OnPropertyChanged(nameof(CanEditTicket));
    partial void OnSelectedConcernChanged(ConcernRecord? value)
    { ReviewResponse=value?.Response??""; ReviewStatus=value?.Status=="Closed"?"Closed":"Under review"; }
    partial void OnSelectedTicketChanged(TicketRecord? value)
    {
        if(applyingTicket) return;
        DetailsLoaded=false;History.Clear();TicketStatus=value?.Status??"Open";TicketNote="";
        SelectedAssignee=Assignees.FirstOrDefault(row=>row.UserId==value?.AssignedToUserId);
        OnPropertyChanged(nameof(CanEditTicket));
        if(value is not null && !IsBusy) LoadSelectedTicketCommand.Execute(null);
    }

    [RelayCommand] private void NewConcern() { ShowIntake=true;Message=""; }
    [RelayCommand] private void CloseIntake() => ShowIntake=false;
    [RelayCommand] private void ResetDraft()
    { requestId=Guid.NewGuid();SelectedAccount=null;Subject="";Description="";Category=Categories[0]; }
    [RelayCommand(CanExecute=nameof(Available))]
    private Task LoadAccountsAsync() => Run(async()=>Replace(Accounts,await client.AccountsAsync(AccountSearch)));
    [RelayCommand(CanExecute=nameof(Available))]
    private Task LoadConcernsAsync() => Run(async()=>
    {
        var rows=await client.ConcernsAsync(ConcernSearch,ConcernFilter=="All"?null:ConcernFilter);
        var selectedId=SelectedConcern?.Id;var draftResponse=ReviewResponse;var draftStatus=ReviewStatus; Replace(Concerns,rows);
        SelectedConcern=rows.FirstOrDefault(row=>row.Id==selectedId);
        if(SelectedConcern is not null && !string.IsNullOrWhiteSpace(draftResponse)) { ReviewResponse=draftResponse;ReviewStatus=draftStatus; }
        if(Accounts.Count==0) Replace(Accounts,await client.AccountsAsync());
        Message=rows.Count==0?"No concerns match these filters.":$"Showing {rows.Count} concerns (up to 500 most recent matches).";
    });
    [RelayCommand(CanExecute=nameof(Available))]
    private Task SaveConcernAsync() => Run(async()=>
    {
        if(SelectedAccount is null) { Message="Select the service account for this report.";return; }
        WorkflowRules.Required(Subject,"Subject",160);WorkflowRules.Required(Description,"Description",3000);
        var saved=await client.CreateConcernAsync(new(requestId,SelectedAccount.Id,Category,Subject,Description));
        Concerns.Insert(0,saved);SelectedConcern=saved;ResetDraft();ShowIntake=false;
        Message="Concern saved. The report is ready for review.";
    });
    [RelayCommand(CanExecute=nameof(CanReview))]
    private Task SaveReviewAsync() => Run(async()=>
    {
        if(SelectedConcern is not { } selected) return;
        var saved=await client.ReviewConcernAsync(selected.Id,new(selected.Version,ReviewStatus,ReviewResponse));
        ReplaceConcern(saved);Message="Review saved and confirmed by the office service.";
    });
    [RelayCommand(CanExecute=nameof(CanDispatch))]
    private Task CreateRepairTicketAsync() => Run(async()=>
    {
        if(SelectedConcern is not { } selected) return;
        WorkflowRules.Required(CreationNote,"Ticket note",3000);
        var saved=await client.CreateTicketAsync(new(selected.Id,selected.Version,CreationNote));
        ReplaceConcern(selected with { TicketId=saved.Ticket.Id });
        if(!Tickets.Any(row=>row.Id==saved.Ticket.Id)) Tickets.Insert(0,saved.Ticket);
        ApplyTicket(saved);CreationNote="";Message="Repair ticket created with its first history entry.";
        TicketCreated?.Invoke();
        if(IsAdmin) { try { Replace(Assignees,await client.AssigneesAsync()); } catch(SessionClientException) { Message+=" Refresh tickets to load staff choices."; } }
    });
    [RelayCommand(CanExecute=nameof(Available))]
    private Task LoadTicketsAsync() => Run(async()=>
    {
        var rows=await client.TicketsAsync(TicketSearch,TicketFilter=="All"?null:TicketFilter);
        var selectedId=SelectedTicket?.Id;var draftNote=TicketNote;var draftStatus=TicketStatus;var draftAssignee=SelectedAssignee?.UserId;Replace(Tickets,rows);
        if(IsAdmin) Replace(Assignees,await client.AssigneesAsync());
        SelectedTicket=rows.FirstOrDefault(row=>row.Id==selectedId);
        if(SelectedTicket is not null)
        {
            ApplyTicket(await client.TicketAsync(SelectedTicket.Id));
            if(!string.IsNullOrWhiteSpace(draftNote)) { TicketNote=draftNote;if(NextTicketStates.Contains(draftStatus))TicketStatus=draftStatus;
                if(IsAdmin) SelectedAssignee=Assignees.FirstOrDefault(row=>row.UserId==draftAssignee); }
        }
        Message=rows.Count==0?"No repair tickets match these filters.":$"Showing {rows.Count} tickets (up to 500 most recent matches).";
    });
    [RelayCommand(CanExecute=nameof(TicketAvailable))]
    private Task LoadSelectedTicketAsync() => Run(async()=>
    { if(SelectedTicket is not null)
        {
            var draftNote=TicketNote;var draftStatus=TicketStatus;var draftAssignee=SelectedAssignee?.UserId;
            ApplyTicket(await client.TicketAsync(SelectedTicket.Id));
            if(!string.IsNullOrWhiteSpace(draftNote)) { TicketNote=draftNote;if(NextTicketStates.Contains(draftStatus))TicketStatus=draftStatus;
                if(IsAdmin) SelectedAssignee=Assignees.FirstOrDefault(row=>row.UserId==draftAssignee); }
        } });
    [RelayCommand(CanExecute=nameof(CanEditTicket))]
    private Task SaveTicketAsync() => Run(async()=>
    {
        if(SelectedTicket is not { } selected) return;
        WorkflowRules.Required(TicketNote,"Update note",3000);
        var assignee=IsAdmin?SelectedAssignee?.UserId:selected.AssignedToUserId;
        var saved=await client.UpdateTicketAsync(selected.Id,new(selected.Version,TicketStatus,assignee,TicketNote));
        ApplyTicket(saved);TicketNote="";Message="Ticket update saved with its history entry.";
        if(saved.Ticket.Status=="Resolved" && SelectedConcern?.Id==saved.Ticket.ConcernId)
            ReplaceConcern(SelectedConcern with { Status="Resolved",Response=saved.Ticket.LatestUpdate });
    });
    private void ApplyTicket(TicketDetails details)
    {
        applyingTicket=true;
        try
        {
            var previous=Tickets.FirstOrDefault(row=>row.Id==details.Ticket.Id);
            if(previous is not null) Tickets[Tickets.IndexOf(previous)]=details.Ticket;
            SelectedTicket=details.Ticket;TicketStatus=details.Ticket.Status;
            SelectedAssignee=Assignees.FirstOrDefault(row=>row.UserId==details.Ticket.AssignedToUserId);
            Replace(History,details.History);DetailsLoaded=true;
        }
        finally { applyingTicket=false; }
    }
    private void ReplaceConcern(ConcernRecord saved)
    {
        var previous=Concerns.FirstOrDefault(row=>row.Id==saved.Id);
        if(previous is not null) Concerns[Concerns.IndexOf(previous)]=saved;
        SelectedConcern=saved;
    }
    private async Task Run(Func<Task> operation)
    {
        if(IsBusy) return;
        IsBusy=true;Message="";
        try { await operation(); }
        catch(SessionClientException failure) { Message=failure.Message;if(failure.RequiresSignIn) SessionLost?.Invoke(failure); }
        catch(WorkflowException failure) { Message=failure.Message; }
        finally { IsBusy=false; }
    }
    private static void Replace<T>(ObservableCollection<T> target,IEnumerable<T> rows)
    { target.Clear();foreach(var row in rows) target.Add(row); }
    public void Clear()
    {
        Accounts.Clear();Assignees.Clear();Concerns.Clear();Tickets.Clear();History.Clear();
        SelectedConcern=null;SelectedTicket=null;DetailsLoaded=false;ResetDraft();ReviewResponse="";CreationNote="";TicketNote="";
        Message="";ShowIntake=false;ConcernSearch="";TicketSearch="";IsAdmin=false;
    }
}
