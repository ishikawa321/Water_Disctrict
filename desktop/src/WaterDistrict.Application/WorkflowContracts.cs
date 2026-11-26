namespace WaterDistrict.Application;

public sealed record AccountOption(Guid Id, string AccountNumber, string HolderName, string ServiceAddress)
{
    public string Label => $"{AccountNumber} / {HolderName}";
}
public sealed record ConcernRecord(Guid Id, Guid AccountId, string AccountNumber, string HolderName,
    string Category, string Subject, string Description, string Status, string? Response,
    DateTimeOffset CreatedAt, DateTimeOffset? ReviewedAt, Guid? TicketId, uint Version,
    double? Latitude = null, double? Longitude = null, string? LocationNote = null)
{
    public string Label => $"{AccountNumber} | {Subject} | {Status}";
}
public sealed record TicketRecord(Guid Id, Guid ConcernId, string AccountNumber, string Subject,
    string Status, string? AssignedTo, Guid? AssignedToUserId, string LatestUpdate,
    DateTimeOffset UpdatedAt, uint Version)
{
    public string Label => $"{AccountNumber} | {Subject} | {Status}";
}
public sealed record HistoryRecord(long Id, string Status, string Note, string ChangedBy,
    string? AssignedTo, DateTimeOffset ChangedAt);
public sealed record TicketDetails(TicketRecord Ticket, IReadOnlyList<HistoryRecord> History);
public sealed record CreateConcern(Guid RequestId, Guid AccountId, string Category, string Subject, string Description,
    double? Latitude = null, double? Longitude = null, string? LocationNote = null);
public sealed record ReviewConcern(uint Version, string Status, string? Response);
public sealed record CreateTicket(Guid ConcernId, uint ConcernVersion, string Note);
public sealed record UpdateTicket(uint Version, string Status, Guid? AssignedToUserId, string Note);

public interface IWorkflowService
{
    Task<IReadOnlyList<AccountOption>> AccountsAsync(SessionProfile actor, string? search, CancellationToken token);
    Task<IReadOnlyList<StaffMember>> AssigneesAsync(SessionProfile actor, CancellationToken token);
    Task<IReadOnlyList<ConcernRecord>> ConcernsAsync(SessionProfile actor, string? search, string? status, CancellationToken token);
    Task<ConcernRecord> ConcernAsync(SessionProfile actor, Guid id, CancellationToken token);
    Task<ConcernRecord> CreateConcernAsync(SessionProfile actor, CreateConcern input, CancellationToken token);
    Task<ConcernRecord> ReviewConcernAsync(SessionProfile actor, Guid id, ReviewConcern input, CancellationToken token);
    Task<IReadOnlyList<TicketRecord>> TicketsAsync(SessionProfile actor, string? search, string? status, CancellationToken token);
    Task<TicketDetails> TicketAsync(SessionProfile actor, Guid id, CancellationToken token);
    Task<TicketDetails> CreateTicketAsync(SessionProfile actor, CreateTicket input, CancellationToken token);
    Task<TicketDetails> UpdateTicketAsync(SessionProfile actor, Guid id, UpdateTicket input, CancellationToken token);
}

public interface IWorkflowClient
{
    Task<IReadOnlyList<AccountOption>> AccountsAsync(string? search = null, CancellationToken token = default);
    Task<IReadOnlyList<StaffMember>> AssigneesAsync(CancellationToken token = default);
    Task<IReadOnlyList<ConcernRecord>> ConcernsAsync(string? search = null, string? status = null, CancellationToken token = default);
    Task<ConcernRecord> ConcernAsync(Guid id, CancellationToken token = default);
    Task<ConcernRecord> CreateConcernAsync(CreateConcern input, CancellationToken token = default);
    Task<ConcernRecord> ReviewConcernAsync(Guid id, ReviewConcern input, CancellationToken token = default);
    Task<IReadOnlyList<TicketRecord>> TicketsAsync(string? search = null, string? status = null, CancellationToken token = default);
    Task<TicketDetails> TicketAsync(Guid id, CancellationToken token = default);
    Task<TicketDetails> CreateTicketAsync(CreateTicket input, CancellationToken token = default);
    Task<TicketDetails> UpdateTicketAsync(Guid id, UpdateTicket input, CancellationToken token = default);
}
