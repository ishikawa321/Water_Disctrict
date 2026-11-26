namespace WaterDistrict.Domain;

public sealed class ServiceAccount
{
    public Guid Id { get; set; }
    public string AccountNumber { get; set; } = "";
    public string HolderName { get; set; } = "";
    public string ServiceAddress { get; set; } = "";
    public bool Active { get; set; }
}

public sealed class ServiceConcern
{
    public Guid Id { get; set; }
    public Guid AccountId { get; set; }
    public Guid SubmittedBy { get; set; }
    public string Category { get; set; } = "";
    public string Subject { get; set; } = "";
    public string Description { get; set; } = "";
    public string Status { get; set; } = "Submitted";
    public string? AdminResponse { get; set; }
    public Guid? ReviewedBy { get; set; }
    public DateTimeOffset? ReviewedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? RepairDispatchedAt { get; set; }
    public uint Version { get; set; }
    public ServiceAccount Account { get; set; } = null!;
}

public sealed class RepairTicket
{
    public Guid Id { get; set; }
    public Guid ConcernId { get; set; }
    public Guid CreatedBy { get; set; }
    public Guid UpdatedBy { get; set; }
    public string? AssignedTo { get; set; }
    public Guid? AssignedToUserId { get; set; }
    public string Status { get; set; } = "Open";
    public string LatestUpdate { get; set; } = "";
    public DateTimeOffset UpdatedAt { get; set; }
    public uint Version { get; set; }
    public ServiceConcern Concern { get; set; } = null!;
}

public sealed class TicketStatusHistory
{
    public long Id { get; set; }
    public Guid TicketId { get; set; }
    public Guid ChangedBy { get; set; }
    public string Status { get; set; } = "";
    public string Note { get; set; } = "";
    public Guid? AssignedToUserId { get; set; }
    public string? AssignedTo { get; set; }
    public DateTimeOffset ChangedAt { get; set; }
    public RepairTicket Ticket { get; set; } = null!;
}
