using Microsoft.EntityFrameworkCore;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;
using WaterDistrictConnect.Core.Persistence;

namespace WaterDistrictConnect.Core.Application;
public sealed partial class WaterService(IDbContextFactory<WaterDbContext> factory, Session session)
{
    private static IQueryable<ServiceConcern> Scope(WaterDbContext db, Identity who) => who.Has(Permissions.ReadOffice) ? db.Concerns : db.Concerns.Where(x => x.CustomerAccountId == who.AccountId && who.IsClient);
    private static ConcernRow Row(ServiceConcern c) => new(c.Id, c.Reference, c.Subject, c.Category, c.State, c.SubmittedAt, c.CustomerAccount.ToString(), c.Version, c.CustomerAccount.Number);
    private static TicketRow Row(RepairTicket t) => new(t.Id, t.Reference, t.ServiceConcern.Reference, t.ServiceConcern.Subject, t.State, t.PlumberResource?.Name ?? "Not assigned", t.CreatedAt, t.Version);
    private static void Fresh(Guid actual, Guid expected) { if (actual != expected) throw new BusinessException("This record changed. Refresh the details and review the latest decision before retrying."); }
    private static void Audit(WaterDbContext db, Identity who, Guid id, string operation) => db.Audits.Add(new() { ActorId = who.Id, RecordId = id, Operation = operation });
    private static void RequireRepairPhase() => throw new BusinessException("Repair-ticket processing is not available until Phase 3.");
    public async Task<Guid> CreateTicketAsync(Guid concernId, Guid version)
    {
        RequireRepairPhase();
        await using var db = await factory.CreateDbContextAsync(); var who = await Access.CurrentAsync(db, session); Access.Require(who, Permissions.Repair);
        await using var tx = await db.Database.BeginTransactionAsync();
        var c = await db.Concerns.Include(x => x.Ticket).SingleOrDefaultAsync(x => x.Id == concernId) ?? throw new BusinessException("Concern unavailable."); Fresh(c.Version, version);
        if (c.Category != ConcernCategory.OtherTechnicalConcern || c.State == ConcernState.Closed) throw new BusinessException("Only an open technical concern can generate a repair ticket.");
        if (c.Ticket != null) throw new BusinessException("This concern already has a repair ticket.");
        var ticket = new RepairTicket { ServiceConcernId = c.Id }; db.Tickets.Add(ticket); c.State = ConcernState.AwaitingRepair; c.Version = Guid.NewGuid();
        await db.SaveChangesAsync();
        db.TicketEvents.Add(new() { RepairTicketId = ticket.Id, ActorId = who.Id, Action = "Created", Text = "Repair ticket created by office personnel.", From = TicketState.Unassigned, To = TicketState.Unassigned });
        db.ConcernEvents.Add(new() { ServiceConcernId = c.Id, ActorId = who.Id, Kind = "Repair ticket", Text = $"Linked repair ticket {ticket.Reference} created." }); Audit(db, who, ticket.Id, "Ticket created");
        await db.SaveChangesAsync(); await tx.CommitAsync(); return ticket.Id;
    }
    public async Task<Page<TicketRow>> TicketsAsync(string search = "", TicketState? state = null, int page = 1, Guid? accountId = null)
    {
        await using var db = await factory.CreateDbContextAsync(); var who = await Access.CurrentAsync(db, session); if (accountId.HasValue) Access.Account(who, accountId.Value);
        var q = db.Tickets.AsNoTracking().Where(x => who.Has(Permissions.ReadOffice) || (who.IsClient && x.ServiceConcern.CustomerAccountId == who.AccountId));
        if (accountId.HasValue) q = q.Where(x => x.ServiceConcern.CustomerAccountId == accountId);
        if (!string.IsNullOrWhiteSpace(search)) { search = search.Trim().ToLowerInvariant(); q = q.Where(x => x.Reference.ToLower().Contains(search) || x.ServiceConcern.Subject.ToLower().Contains(search) || x.ServiceConcern.Reference.ToLower().Contains(search)); }
        if (state.HasValue) q = q.Where(x => x.State == state);
        var count = await q.CountAsync(); page = Math.Clamp(page, 1, Math.Max(1, (count + 19) / 20));
        var items = await q.Include(x => x.ServiceConcern).Include(x => x.PlumberResource).OrderByDescending(x => x.CreatedAt).ThenBy(x => x.Id).Skip((page - 1) * 20).Take(20).ToArrayAsync();
        return new(items.Select(Row).ToArray(), count, page, 20);
    }
    public async Task<TicketDetail> TicketAsync(Guid id)
    {
        await using var db = await factory.CreateDbContextAsync(); var who = await Access.CurrentAsync(db, session);
        var t = await db.Tickets.AsNoTracking().Include(x => x.ServiceConcern).Include(x => x.PlumberResource).SingleOrDefaultAsync(x => x.Id == id && (who.Has(Permissions.ReadOffice) || (who.IsClient && x.ServiceConcern.CustomerAccountId == who.AccountId))) ?? throw new BusinessException("Record unavailable for this account.");
        var events = await db.TicketEvents.AsNoTracking().Where(x => x.RepairTicketId == id && (!x.Internal || who.Has(Permissions.ReadOffice))).Include(x => x.Actor).Include(x => x.PlumberResource).OrderBy(x => x.At).ToArrayAsync();
        return new(Row(t), t.ServiceConcernId, t.ServiceConcern.Location, t.CompletionSummary, t.SignedJobOrder, t.FirstAssignedAt, events.Select(x => new TimelineRow(x.At, $"{x.Action}: {x.From} → {x.To}", x.Text + (who.IsClient || x.PlumberResource == null ? "" : $" · Resource: {x.PlumberResource.Name}"), x.Internal, who.IsClient ? "Office personnel" : x.Actor.DisplayName)).ToArray());
    }
    public async Task UpdateTicketAsync(Guid id, Guid version, TicketAction action, string text, Guid? plumberId = null, bool internalNote = false)
    {
        RequireRepairPhase();
        if (internalNote && action != TicketAction.Progress) throw new BusinessException("State decisions must be customer visible; use Progress for an internal note.");
        await using var db = await factory.CreateDbContextAsync(); var who = await Access.CurrentAsync(db, session); Access.Require(who, Permissions.Repair);
        await using var tx = await db.Database.BeginTransactionAsync();
        var t = await db.Tickets.Include(x => x.ServiceConcern).SingleOrDefaultAsync(x => x.Id == id) ?? throw new BusinessException("Ticket unavailable."); Fresh(t.Version, version);
        var resource = action == TicketAction.Assign ? await db.Plumbers.SingleOrDefaultAsync(x => x.Id == plumberId) : null;
        var previous = t.State; var now = DateTimeOffset.UtcNow; TicketPolicy.Apply(t, action, text, resource, now);
        t.ServiceConcern.State = action == TicketAction.Close ? ConcernState.Closed : ConcernState.AwaitingRepair; t.ServiceConcern.Version = Guid.NewGuid();
        await db.SaveChangesAsync(); // Essential state write; a later history failure must undo it.
        db.TicketEvents.Add(new() { RepairTicketId = id, ActorId = who.Id, At = now, Action = action.ToString(), From = previous, To = t.State, Text = text.Trim(), Internal = internalNote, PlumberResourceId = t.PlumberResourceId });
        Audit(db, who, id, "Ticket " + action); await db.SaveChangesAsync(); await tx.CommitAsync();
    }
    public async Task<CustomerAccount[]> AccountsAsync(string search = "")
    {
        await using var db = await factory.CreateDbContextAsync(); var who = await Access.CurrentAsync(db, session);
        var q = db.Accounts.AsNoTracking().Where(x => who.Has(Permissions.ReadOffice) || (who.IsClient && x.Id == who.AccountId));
        if (!string.IsNullOrWhiteSpace(search)) { search = search.Trim().ToLowerInvariant(); q = q.Where(x => x.Number.Contains(search) || x.Name.ToLower().Contains(search)); }
        return await q.OrderBy(x => x.Number).Take(100).ToArrayAsync();
    }
    public async Task<PlumberResource[]> PlumbersAsync()
    {
        await using var db = await factory.CreateDbContextAsync(); Access.Require(await Access.CurrentAsync(db, session), Permissions.ReadOffice);
        return await db.Plumbers.AsNoTracking().OrderBy(x => x.Name).ToArrayAsync();
    }
    public async Task<Overview> OverviewAsync()
    {
        await using var db = await factory.CreateDbContextAsync(); var who = await Access.CurrentAsync(db, session); var q = Scope(db, who);
        var tq = db.Tickets.Where(x => who.Has(Permissions.ReadOffice) || (who.IsClient && x.ServiceConcern.CustomerAccountId == who.AccountId));
        var recent = await q.AsNoTracking().Include(x => x.CustomerAccount).OrderByDescending(x => x.SubmittedAt).Take(5).ToArrayAsync();
        var ce = await db.ConcernEvents.AsNoTracking().Where(x => (who.Has(Permissions.ReadOffice) || (who.IsClient && x.ServiceConcern.CustomerAccountId == who.AccountId)) && (!x.Internal || who.Has(Permissions.ReadOffice))).OrderByDescending(x => x.At).Take(8).Select(x => new TimelineRow(x.At, x.Kind, x.Text, x.Internal, who.IsClient ? "Office / receipt" : x.Actor.DisplayName)).ToArrayAsync();
        var te = await db.TicketEvents.AsNoTracking().Where(x => (who.Has(Permissions.ReadOffice) || (who.IsClient && x.RepairTicket.ServiceConcern.CustomerAccountId == who.AccountId)) && (!x.Internal || who.Has(Permissions.ReadOffice))).OrderByDescending(x => x.At).Take(8).Select(x => new TimelineRow(x.At, x.Action, x.Text, x.Internal, who.IsClient ? "Office personnel" : x.Actor.DisplayName)).ToArrayAsync();
        return new(await q.CountAsync(), await q.CountAsync(x => x.State == ConcernState.Submitted), await tq.CountAsync(), await tq.CountAsync(x => x.State == TicketState.Unassigned), await tq.CountAsync(x => x.State == TicketState.Assigned || x.State == TicketState.InProgress), recent.Select(Row).ToArray(), ce.Concat(te).OrderByDescending(x => x.At).Take(8).ToArray());
    }
}
