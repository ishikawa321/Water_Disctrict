namespace WaterDistrict.Application;

public sealed record OfficeAccount(Guid Id,string AccountNumber,string HolderName,string ServiceAddress,bool Active)
{
    public string Label=>$"{AccountNumber} / {HolderName}";
}
public sealed record OfficeRegistration(Guid UserId,string FullName,string ServiceAddress,string Email,string Status,DateTimeOffset SubmittedAt,DateTimeOffset? EmailConfirmedAt)
{ public string Label=>$"{FullName} / {Email} / {ServiceAddress}"; }
public sealed record RegistrationApproval(string AccountNumber);
public sealed record OfficeBill(Guid Id,string BillNumber,string AccountNumber,DateOnly PeriodStart,DateOnly PeriodEnd,DateOnly DueDate,decimal AmountDue,decimal Paid)
{
    public decimal Remaining=>Math.Max(0,AmountDue-Paid);
    public string Label=>$"{BillNumber} / {AccountNumber} / {Remaining:N2} remaining";
}
public sealed record OfficePayment(string ReceiptReference,string BillNumber,string AccountNumber,DateOnly PaymentDate,decimal AmountPaid,DateTimeOffset? VerifiedAt);
public sealed record OfficeAnnouncement(Guid Id,string Title,string Message,bool Published,DateTimeOffset UpdatedAt)
{
    public const string InterruptionPrefix="[Service interruption] ";
    public bool IsInterruption=>Title.StartsWith(InterruptionPrefix,StringComparison.Ordinal);
    public string DisplayTitle=>IsInterruption?Title[InterruptionPrefix.Length..]:Title;
    public string Label=>$"{DisplayTitle} / {(Published?"Published":"Draft")}";
}
public sealed record OfficeSummary(int PendingConcerns,int ActiveRepairs);
public sealed record AddOfficeBill(Guid AccountId,string BillNumber,DateOnly PeriodStart,DateOnly PeriodEnd,DateOnly DueDate,decimal AmountDue);
public sealed record AddOfficePayment(Guid BillId,string ReceiptReference,DateOnly PaymentDate,decimal AmountPaid,bool Verified);
public sealed record SaveOfficeAnnouncement(string Title,string Message,bool Published,bool IsInterruption);

public interface IOfficeClient
{
    Task<IReadOnlyList<OfficeRegistration>> RegistrationsAsync(CancellationToken token=default);
    Task<RegistrationApproval> ApproveRegistrationAsync(Guid id,CancellationToken token=default);
    Task<OfficeSummary> SummaryAsync(CancellationToken token=default);
    Task<IReadOnlyList<OfficeAccount>> OfficeAccountsAsync(CancellationToken token=default);
    Task<IReadOnlyList<OfficeBill>> BillsAsync(CancellationToken token=default);
    Task<OfficeBill> AddBillAsync(AddOfficeBill input,CancellationToken token=default);
    Task<IReadOnlyList<OfficePayment>> PaymentsAsync(CancellationToken token=default);
    Task<OfficePayment> AddPaymentAsync(AddOfficePayment input,CancellationToken token=default);
    Task<IReadOnlyList<OfficeAnnouncement>> AnnouncementsAsync(CancellationToken token=default);
    Task<OfficeAnnouncement> SaveAnnouncementAsync(Guid? id,SaveOfficeAnnouncement input,CancellationToken token=default);
}
public interface IOfficeService
{
    Task<IReadOnlyList<OfficeRegistration>> RegistrationsAsync(SessionProfile actor,string bearer,CancellationToken token);
    Task<RegistrationApproval> ApproveRegistrationAsync(SessionProfile actor,string bearer,Guid id,CancellationToken token);
    Task<OfficeSummary> SummaryAsync(SessionProfile actor,string bearer,CancellationToken token);
    Task<IReadOnlyList<OfficeAccount>> AccountsAsync(SessionProfile actor,string bearer,CancellationToken token);
    Task<IReadOnlyList<OfficeBill>> BillsAsync(SessionProfile actor,string bearer,CancellationToken token);
    Task<OfficeBill> AddBillAsync(SessionProfile actor,string bearer,AddOfficeBill input,CancellationToken token);
    Task<IReadOnlyList<OfficePayment>> PaymentsAsync(SessionProfile actor,string bearer,CancellationToken token);
    Task<IReadOnlyList<OfficePayment>> PaymentsForBillAsync(SessionProfile actor,string bearer,Guid billId,CancellationToken token);
    Task<OfficePayment> AddPaymentAsync(SessionProfile actor,string bearer,AddOfficePayment input,CancellationToken token);
    Task<IReadOnlyList<OfficeAnnouncement>> AnnouncementsAsync(SessionProfile actor,string bearer,CancellationToken token);
    Task<OfficeAnnouncement> SaveAnnouncementAsync(SessionProfile actor,string bearer,Guid? id,SaveOfficeAnnouncement input,CancellationToken token);
}
