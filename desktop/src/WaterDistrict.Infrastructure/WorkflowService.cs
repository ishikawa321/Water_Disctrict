using System.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using WaterDistrict.Application;
using WaterDistrict.Domain;

namespace WaterDistrict.Infrastructure;

public sealed class WorkflowService(WaterDistrictDbContext db) : IWorkflowService
{
    private bool schemaVerified;
    private async Task<AppProfile> Actor(SessionProfile supplied, CancellationToken token, bool admin = false)
    {
        if (!schemaVerified)
        {
            var applied = await db.Database.GetAppliedMigrationsAsync(token);
            if (db.Database.GetMigrations().Except(applied).Any())
                throw new DependencyUnavailableException("Apply the reviewed workflow migration before processing records.");
            schemaVerified = true;
        }
        var actor = await db.Profiles.AsNoTracking().SingleOrDefaultAsync(row => row.UserId == supplied.UserId, token);
        if (actor is null || !actor.Active || !AppRoles.HasDesktopAccess(actor.Role) || admin && actor.Role != AppRoles.Admin)
            throw new WorkflowException("forbidden", "Your account does not have permission for this operation.", 403);
        return actor;
    }

    private async Task SetActor(Guid id, CancellationToken token) =>
        await db.Database.ExecuteSqlInterpolatedAsync($"SELECT set_config('request.jwt.claim.sub', {id.ToString()}, true)", token);

    public async Task<IReadOnlyList<AccountOption>> AccountsAsync(SessionProfile actor, string? search, CancellationToken token)
    {
        await Actor(actor, token);
        var query = db.Accounts.AsNoTracking().Where(row => row.Active);
        if (!string.IsNullOrWhiteSpace(search)) query = query.Where(row => EF.Functions.ILike(row.AccountNumber, $"%{search.Trim()}%") || EF.Functions.ILike(row.HolderName, $"%{search.Trim()}%"));
        return await query.OrderBy(row => row.AccountNumber).Take(200)
            .Select(row => new AccountOption(row.Id, row.AccountNumber, row.HolderName, row.ServiceAddress)).ToListAsync(token);
    }

    public async Task<IReadOnlyList<StaffMember>> AssigneesAsync(SessionProfile actor, CancellationToken token)
    {
        await Actor(actor, token, admin: true);
        return await db.Profiles.AsNoTracking().Where(row => row.Active && row.Role == AppRoles.Staff)
            .OrderBy(row => row.DisplayName).Select(row => new StaffMember(row.UserId, row.DisplayName, row.Role)).ToListAsync(token);
    }

    private IQueryable<ConcernRecord> ConcernRows(IQueryable<ServiceConcern> source) => source.Select(row => new ConcernRecord(
        row.Id, row.AccountId, row.Account.AccountNumber, row.Account.HolderName, row.Category, row.Subject,
        row.Description, row.Status, row.AdminResponse, row.CreatedAt, row.ReviewedAt,
        db.Tickets.Where(ticket => ticket.ConcernId == row.Id).Select(ticket => (Guid?)ticket.Id).FirstOrDefault(), row.Version));

    public async Task<IReadOnlyList<ConcernRecord>> ConcernsAsync(SessionProfile actor, string? search, string? status, CancellationToken token)
    {
        await Actor(actor, token);
        var query = db.Concerns.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(row => row.Status == status);
        if (!string.IsNullOrWhiteSpace(search)) query = query.Where(row => EF.Functions.ILike(row.Subject, $"%{search.Trim()}%") || EF.Functions.ILike(row.Account.AccountNumber, $"%{search.Trim()}%"));
        return await ConcernRows(query.OrderByDescending(row => row.CreatedAt).ThenBy(row => row.Id).Take(500)).ToListAsync(token);
    }

    public async Task<ConcernRecord> ConcernAsync(SessionProfile actor, Guid id, CancellationToken token)
    {
        await Actor(actor, token);
        return await ConcernRows(db.Concerns.AsNoTracking().Where(row => row.Id == id)).SingleOrDefaultAsync(token)
            ?? throw new WorkflowException("not_found", "This concern is no longer available.", 404);
    }

    public Task<ConcernRecord> CreateConcernAsync(SessionProfile actor, CreateConcern input, CancellationToken token) => Mutate(async () =>
    {
        await using var transaction = await db.Database.BeginTransactionAsync(token);
        await Actor(actor, token);
        await SetActor(actor.UserId, token);
        if (input.RequestId == Guid.Empty) throw new WorkflowException("validation", "A request identifier is required.");
        var category = WorkflowRules.Required(input.Category, "Category", 80);
        if (!WorkflowRules.Categories.Contains(category)) throw new WorkflowException("category", "Select a supported concern category.");
        var subject = WorkflowRules.Required(input.Subject, "Subject", 150);
        var description = WorkflowRules.Required(input.Description, "Description", 3000);
        var existing = await db.Concerns.AsNoTracking().SingleOrDefaultAsync(row => row.Id == input.RequestId, token);
        if (existing is not null)
        {
            if (existing.SubmittedBy != actor.UserId || existing.AccountId != input.AccountId || existing.Category != category || existing.Subject != subject || existing.Description != description)
                throw new WorkflowException("conflict", "That request identifier is already in use. Refresh before retrying.", 409);
            await transaction.CommitAsync(token);
            return await ConcernAsync(actor, existing.Id, token);
        }
        if (!await db.Accounts.AnyAsync(row => row.Id == input.AccountId && row.Active, token))
            throw new WorkflowException("account", "Select an existing active service account.");
        db.Concerns.Add(new() { Id = input.RequestId, AccountId = input.AccountId, SubmittedBy = actor.UserId,
            Category = category, Subject = subject, Description = description, Status = "Submitted" });
        await db.SaveChangesAsync(token);
        await transaction.CommitAsync(token);
        return await ConcernAsync(actor, input.RequestId, token);
    });

    public Task<ConcernRecord> ReviewConcernAsync(SessionProfile actor, Guid id, ReviewConcern input, CancellationToken token) => Mutate(async () =>
    {
        await using var transaction = await db.Database.BeginTransactionAsync(token);
        await Actor(actor, token);
        await SetActor(actor.UserId, token);
        var concern = await db.Concerns.SingleOrDefaultAsync(row => row.Id == id, token)
            ?? throw new WorkflowException("not_found", "This concern is no longer available.", 404);
        CheckVersion(concern.Version, input.Version);
        WorkflowRules.Review(concern.Status, input.Status, input.Response, await db.Tickets.AnyAsync(row => row.ConcernId == id, token));
        concern.Status = input.Status;
        concern.AdminResponse = string.IsNullOrWhiteSpace(input.Response) ? null : input.Response.Trim();
        concern.ReviewedBy = actor.UserId;
        concern.ReviewedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(token);
        await transaction.CommitAsync(token);
        return await ConcernAsync(actor, id, token);
    });

    private static IQueryable<TicketRecord> TicketRows(IQueryable<RepairTicket> source) => source.Select(row => new TicketRecord(row.Id, row.ConcernId, row.Concern.Account.AccountNumber, row.Concern.Subject,
            row.Status, row.AssignedTo, row.AssignedToUserId, row.LatestUpdate, row.UpdatedAt, row.Version));

    public async Task<IReadOnlyList<TicketRecord>> TicketsAsync(SessionProfile actor, string? search, string? status, CancellationToken token)
    {
        var verified = await Actor(actor, token);
        var query = db.Tickets.AsNoTracking().Where(row => verified.Role != AppRoles.Staff || row.AssignedToUserId == actor.UserId);
        if (!string.IsNullOrWhiteSpace(status)) query = query.Where(row => row.Status == status);
        if (!string.IsNullOrWhiteSpace(search)) query = query.Where(row => EF.Functions.ILike(row.Concern.Subject, $"%{search.Trim()}%") || EF.Functions.ILike(row.Concern.Account.AccountNumber, $"%{search.Trim()}%"));
        return await TicketRows(query.OrderByDescending(row => row.UpdatedAt).ThenBy(row => row.Id).Take(500)).ToListAsync(token);
    }

    public async Task<TicketDetails> TicketAsync(SessionProfile actor, Guid id, CancellationToken token)
    {
        var verified = await Actor(actor, token);
        var ticket = await TicketRows(db.Tickets.AsNoTracking().Where(row => row.Id == id && (verified.Role != AppRoles.Staff || row.AssignedToUserId == actor.UserId))).SingleOrDefaultAsync(token)
            ?? throw new WorkflowException("not_found", "This ticket is unavailable or is not assigned to you.", 404);
        var history = await (from row in db.History.AsNoTracking() join user in db.Profiles on row.ChangedBy equals user.UserId
            where row.TicketId == id orderby row.Id
            select new HistoryRecord(row.Id, row.Status, row.Note, user.DisplayName, row.AssignedTo, row.ChangedAt)).ToListAsync(token);
        return new(ticket, history);
    }

    public Task<TicketDetails> CreateTicketAsync(SessionProfile actor, CreateTicket input, CancellationToken token) => Mutate(async () =>
    {
        await using var transaction = await db.Database.BeginTransactionAsync(token);
        await Actor(actor, token, admin: true);
        await SetActor(actor.UserId, token);
        // Lock the concern until ticket/history/dispatch writes have committed.
        var concern = await db.Concerns.FromSqlInterpolated($"SELECT *, xmin FROM public.service_concerns WHERE id = {input.ConcernId} FOR UPDATE")
            .SingleOrDefaultAsync(token) ?? throw new WorkflowException("not_found", "This concern is no longer available.", 404);
        CheckVersion(concern.Version, input.ConcernVersion);
        if (concern.Status != "Under review" || concern.ReviewedBy is null || concern.ReviewedAt is null)
            throw new WorkflowException("review", "Review the concern before creating a repair ticket.");
        if (await db.Tickets.AnyAsync(row => row.ConcernId == input.ConcernId, token))
            throw new WorkflowException("duplicate", "A ticket already exists for this concern. Refresh the list.", 409);
        var note = WorkflowRules.Required(input.Note, "Ticket note", 3000);
        var id = Guid.NewGuid();
        db.Tickets.Add(new() { Id = id, ConcernId = input.ConcernId, Status = "Open", LatestUpdate = note,
            CreatedBy = actor.UserId, UpdatedBy = actor.UserId });
        // Database triggers enforce the same atomic history/dispatch outcome for every writer.
        await db.SaveChangesAsync(token);
        await transaction.CommitAsync(token);
        return await TicketAsync(actor, id, token);
    });

    public Task<TicketDetails> UpdateTicketAsync(SessionProfile actor, Guid id, UpdateTicket input, CancellationToken token) => Mutate(async () =>
    {
        await using var transaction = await db.Database.BeginTransactionAsync(token);
        var verified = await Actor(actor, token);
        await SetActor(actor.UserId, token);
        var ticket = await db.Tickets.SingleOrDefaultAsync(row => row.Id == id, token)
            ?? throw new WorkflowException("not_found", "This ticket is no longer available.", 404);
        CheckVersion(ticket.Version, input.Version);
        if (verified.Role == AppRoles.Staff && (ticket.AssignedToUserId != actor.UserId || input.AssignedToUserId != actor.UserId))
            throw new WorkflowException("forbidden", "Staff can update only their own assigned tickets and cannot reassign them.", 403);
        WorkflowRules.TicketTransition(ticket.Status, input.Status, input.AssignedToUserId, input.Note);
        AppProfile? assignee = null;
        if (input.AssignedToUserId is Guid assigneeId)
        {
            assignee = await db.Profiles.AsNoTracking().SingleOrDefaultAsync(row => row.UserId == assigneeId && row.Active && row.Role == AppRoles.Staff, token);
            if (assignee is null) throw new WorkflowException("assignee", "The selected staff member is inactive or unavailable.");
        }
        ticket.Status = input.Status;
        ticket.AssignedToUserId = assignee?.UserId;
        ticket.AssignedTo = assignee?.DisplayName;
        ticket.LatestUpdate = input.Note.Trim();
        ticket.UpdatedBy = actor.UserId;
        await db.SaveChangesAsync(token);
        await transaction.CommitAsync(token);
        return await TicketAsync(actor, id, token);
    });

    private static void CheckVersion(uint current, uint supplied)
    {
        if (supplied == 0 || supplied != current)
            throw new WorkflowException("conflict", "This record changed. Reload it and review the latest information before saving.", 409);
    }

    private async Task<T> Mutate<T>(Func<Task<T>> operation)
    {
        try { return await operation(); }
        catch (DbUpdateConcurrencyException)
        { db.ChangeTracker.Clear(); throw new WorkflowException("conflict", "Another user changed this record. Reload before saving.", 409); }
        catch (DbUpdateException exception) when (exception.InnerException is PostgresException pg && pg.SqlState is "23505" or "23503" or "23514" or "42501")
        {
            db.ChangeTracker.Clear();
            var status = pg.SqlState == "42501" ? 403 : pg.SqlState == "23514" ? 422 : 409;
            throw new WorkflowException("database_rule", pg.SqlState == "23505" ? "This record already exists. Refresh before retrying."
                : "The database rejected the operation. Check the account, assignment and current status, then reload.", status);
        }
    }
}
