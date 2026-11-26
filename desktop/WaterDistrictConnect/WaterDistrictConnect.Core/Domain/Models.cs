namespace WaterDistrictConnect.Core.Domain;

public enum ConcernCategory { OtherTechnicalConcern = 0, GeneralInquiry = 1, BillingPaymentInquiry = 2, WaterLeak = 3, LowNoWaterSupply = 4 }
public enum ConcernState { Submitted = 0, UnderReview = 1, AwaitingRepair = 2, Closed = 3, Resolved = 4 }
public enum IntakeChannel { DesktopClient, Telephone, WalkIn, Other }
public enum ConcernAction { Review, Respond, InternalNote, Reclassify, Resolve, Close, Reopen }
public enum TicketState { Unassigned, Assigned, InProgress, Resolved, Closed }
public enum TicketAction { Assign, Start, Progress, Resolve, Close, Reopen }
public static class Permissions
{
    public const string ReadOffice = "office.read", Intake = "concern.intake", Respond = "concern.respond", Repair = "ticket.process", Client = "client.own";
}
public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Username { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public bool Active { get; set; } = true;
    public List<UserRole> Roles { get; set; } = [];
    public List<AccountOwnership> Ownerships { get; set; } = [];
}
public class Role { public int Id { get; set; } public string Name { get; set; } = ""; public List<RolePermission> Permissions { get; set; } = []; }
public class RolePermission { public int RoleId { get; set; } public Role Role { get; set; } = null!; public string Permission { get; set; } = ""; }
public class UserRole { public Guid UserId { get; set; } public User User { get; set; } = null!; public int RoleId { get; set; } public Role Role { get; set; } = null!; }
public class CustomerAccount
{
    public Guid Id { get; set; } = Guid.NewGuid(); public string Number { get; set; } = ""; public string Name { get; set; } = ""; public string Address { get; set; } = "";
    public override string ToString() => $"{Number} · {Name}";
}
public class AccountOwnership { public Guid UserId { get; set; } public User User { get; set; } = null!; public Guid CustomerAccountId { get; set; } public CustomerAccount CustomerAccount { get; set; } = null!; }
public class ServiceConcern
{
    public Guid Id { get; set; } = Guid.NewGuid(); public string Reference { get; set; } = null!;
    public Guid SubmissionKey { get; set; } = Guid.NewGuid();
    public Guid CustomerAccountId { get; set; } public CustomerAccount CustomerAccount { get; set; } = null!;
    public Guid RecordedById { get; set; } public User RecordedBy { get; set; } = null!;
    public IntakeChannel IntakeChannel { get; set; } = IntakeChannel.DesktopClient;
    public string? LegacyIntakeChannel { get; set; }
    public ConcernCategory Category { get; set; } public ConcernState State { get; set; }
    public string Subject { get; set; } = ""; public string Description { get; set; } = ""; public string Location { get; set; } = ""; public string Contact { get; set; } = "";
    public DateTimeOffset SubmittedAt { get; set; } = DateTimeOffset.UtcNow; public DateTimeOffset? FirstHumanResponseAt { get; set; }
    public Guid Version { get; set; } = Guid.NewGuid();
    public RepairTicket? Ticket { get; set; } public List<ConcernEvent> Events { get; set; } = [];
}
public class ConcernEvent
{
    public ConcernState? PreviousState { get; set; } public ConcernState? NewState { get; set; }
    public ConcernCategory? PreviousCategory { get; set; } public ConcernCategory? NewCategory { get; set; }
    public Guid Id { get; set; } = Guid.NewGuid(); public Guid ServiceConcernId { get; set; } public ServiceConcern ServiceConcern { get; set; } = null!;
    public Guid ActorId { get; set; } public User Actor { get; set; } = null!;
    public DateTimeOffset At { get; set; } = DateTimeOffset.UtcNow; public string Kind { get; set; } = ""; public string Text { get; set; } = ""; public bool Internal { get; set; }
}
public class PlumberResource
{
    public Guid Id { get; set; } = Guid.NewGuid(); public string Name { get; set; } = ""; public bool Available { get; set; } = true; public string AvailabilityNote { get; set; } = "Demo availability; confirm before assigning.";
    public override string ToString() => Name + (Available ? " · Available" : " · Unavailable");
}
public class RepairTicket
{
    public Guid Id { get; set; } = Guid.NewGuid(); public string Reference { get; set; } = "T-" + Guid.NewGuid().ToString("N")[..12].ToUpperInvariant();
    public Guid ServiceConcernId { get; set; } public ServiceConcern ServiceConcern { get; set; } = null!;
    public Guid? PlumberResourceId { get; set; } public PlumberResource? PlumberResource { get; set; }
    public TicketState State { get; set; } = TicketState.Unassigned;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow; public DateTimeOffset? FirstAssignedAt { get; set; }
    public DateTimeOffset? ResolvedAt { get; set; } public DateTimeOffset? ClosedAt { get; set; }
    public string CompletionSummary { get; set; } = ""; public string SignedJobOrder { get; set; } = "";
    public Guid Version { get; set; } = Guid.NewGuid(); public List<TicketEvent> Events { get; set; } = [];
}
public class TicketEvent
{
    public Guid Id { get; set; } = Guid.NewGuid(); public Guid RepairTicketId { get; set; } public RepairTicket RepairTicket { get; set; } = null!;
    public Guid ActorId { get; set; } public User Actor { get; set; } = null!;
    public DateTimeOffset At { get; set; } = DateTimeOffset.UtcNow; public string Action { get; set; } = ""; public TicketState From { get; set; } public TicketState To { get; set; }
    public string Text { get; set; } = ""; public bool Internal { get; set; } public Guid? PlumberResourceId { get; set; } public PlumberResource? PlumberResource { get; set; }
}
public class AuditRecord
{
    public Guid Id { get; set; } = Guid.NewGuid(); public Guid ActorId { get; set; } public User Actor { get; set; } = null!;
    public DateTimeOffset At { get; set; } = DateTimeOffset.UtcNow; public string Operation { get; set; } = ""; public Guid RecordId { get; set; }
}
