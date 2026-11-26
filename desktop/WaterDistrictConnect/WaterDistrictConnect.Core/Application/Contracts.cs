using WaterDistrictConnect.Core.Domain;
namespace WaterDistrictConnect.Core.Application;
public record ConcernInput(Guid? AccountId, ConcernCategory Category, string Subject, string Description, string Location, string Contact, string Channel, Guid? SubmissionKey = null);
public record ConcernRow(Guid Id, string Reference, string Subject, ConcernCategory Category, ConcernState State, DateTimeOffset SubmittedAt, string Account, Guid Version, string AccountNumber = "")
{
    public bool IsSubmitted => State == ConcernState.Submitted;
    public bool IsResolved => State == ConcernState.Resolved;
    public bool IsClosed => State == ConcernState.Closed;
    public string ShortStateLabel => ConcernLabels.State(State);
    public string CategoryIcon => IconFor(Category);
    public static string IconFor(ConcernCategory category) => category switch {
        ConcernCategory.WaterLeak => "M12,2 C9,7 4,12 4,16 A8,8 0 0 0 20,16 C20,12 15,7 12,2 Z",
        ConcernCategory.LowNoWaterSupply => "M3,9 H19 V14 H15 V12 H3 Z M7,9 V5 H15 V9 M11,5 V2 M7,2 H15 M19,17 C16,20 17,23 19,23 C21,23 22,20 19,17 Z",
        ConcernCategory.OtherTechnicalConcern => "M14,3 A6,6 0 0 0 8,11 L2,17 A3,3 0 0 0 7,22 L14,15 A6,6 0 0 0 22,7 L17,11 13,7 17,3 Z",
        _ => "M5,3 H19 V21 H5 Z M8,7 H16 M8,11 H16 M8,15 H14" };
    public string StateLabel => State == ConcernState.Submitted ? "Received — awaiting office review" : ConcernLabels.State(State);
    public string CategoryLabel => ConcernLabels.Category(Category);
    public string DateLabel => TimeDisplay.Format(SubmittedAt);
}
public record TicketRow(Guid Id, string Reference, string ConcernReference, string Subject, TicketState State, string Plumber, DateTimeOffset CreatedAt, Guid Version)
{
    public string StateLabel => State == TicketState.InProgress ? "In Progress" : State.ToString();
    public string DateLabel => TimeDisplay.Format(CreatedAt);
}
public record TimelineRow(DateTimeOffset At, string Kind, string Text, bool Internal, string Actor, ConcernState? PreviousState = null, ConcernState? NewState = null)
{
    public string DisplayKind => Kind switch { "Receipt" => "Received", "Human response" => "Office response", "Resolve" => "Concern resolved", "Close" => "Concern closed", "Reopen" => "Concern reopened", "Review" => "Under review", _ => Kind };
    public string Header => $"{TimeDisplay.Format(At)} · {Actor}";
    public string StateChange => NewState.HasValue && PreviousState != NewState ? (PreviousState.HasValue ? ConcernLabels.State(PreviousState.Value) + " → " : "") + ConcernLabels.State(NewState.Value) : "";
    public string Visibility => Internal ? "INTERNAL — office only" : "Customer visible";
}
public record ConcernDetail(ConcernRow Row, Guid AccountId, string Description, string Location, string Contact, string Channel, string RecordedBy, DateTimeOffset? FirstResponse, string? TicketReference, TimelineRow[] Timeline);
public record TicketDetail(TicketRow Row, Guid ConcernId, string Location, string Summary, string JobOrder, DateTimeOffset? FirstAssigned, TimelineRow[] Timeline);
public record Page<T>(T[] Items, int Total, int Number, int Size);
public record Overview(int Concerns, int AwaitingReview, int Tickets, int Unassigned, int Active, ConcernRow[] RecentConcerns, TimelineRow[] RecentActivity);
public static class TimeDisplay
{
    public static string Format(DateTimeOffset at) => at.ToOffset(TimeSpan.FromHours(8)).ToString("dd MMM yyyy, h:mm tt") + " PHT";
}

public record ConcernActivity(Guid ConcernId, string Reference, TimelineRow Event);
public record ConcernOverview(int Total, int Submitted, int UnderReview, int Closed, ConcernRow[] Recent,
    int Resolved = 0, ConcernActivity[]? Activity = null, ConcernRow[]? PendingReview = null)
{
    public int Open => Total - Closed - Resolved;
}
