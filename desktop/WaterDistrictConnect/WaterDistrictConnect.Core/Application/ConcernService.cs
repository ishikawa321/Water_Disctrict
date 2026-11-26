using Microsoft.EntityFrameworkCore;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;

namespace WaterDistrictConnect.Core.Application;

public sealed partial class WaterService
{
    public async Task<Guid> SubmitAsync(ConcernInput input)
    {
        var subject = InputRules.Required(input.Subject, "Subject", 160);
        var description = InputRules.Required(input.Description, "Description", 4000);
        var location = InputRules.Required(input.Location, "Service location", 300);
        var contact = InputRules.Optional(input.Contact, "Contact details", 200);
        if (!Enum.IsDefined(input.Category)) throw new BusinessException("Choose a valid concern category.");
        await using var db = await factory.CreateDbContextAsync(); var who = await Access.CurrentAsync(db, session);
        Guid account; IntakeChannel channel;
        if (who.IsClient)
        {
            account = who.AccountId ?? throw new BusinessException("No eligible linked account. Contact the demo administrator.");
            if (input.AccountId.HasValue && input.AccountId != account) throw new BusinessException("Record unavailable for this account.");
            channel = IntakeChannel.DesktopClient;
        }
        else
        {
            Access.Require(who, Permissions.Intake); Access.Require(who, Permissions.ReadOffice);
            account = input.AccountId ?? throw new BusinessException("Select an existing customer account.");
            channel = Enum.GetValues<IntakeChannel>().FirstOrDefault(c => ConcernLabels.Channel(c) == input.Channel, (IntakeChannel)(-1));
            if (!Enum.IsDefined(channel) || channel == IntakeChannel.DesktopClient) throw new BusinessException("Choose Telephone, Walk-in, or Other for office intake.");
        }
        if (!await db.Accounts.AnyAsync(x => x.Id == account)) throw new BusinessException("Customer account is unavailable.");
        var key = input.SubmissionKey ?? Guid.NewGuid();
        if (key == Guid.Empty) throw new BusinessException("Submission reference is invalid. Reopen the submission form.");
        await using var tx = await db.Database.BeginTransactionAsync();
        await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({key.ToString()}, 0))");
        var existing = await db.Concerns.SingleOrDefaultAsync(x => x.SubmissionKey == key);
        if (existing != null)
        {
            if (existing.RecordedById != who.Id || existing.CustomerAccountId != account || existing.Subject != subject || existing.Description != description || existing.Category != input.Category || existing.Location != location || existing.Contact != contact || existing.IntakeChannel != channel)
                throw new BusinessException("This submission was already saved with different details. Find the saved concern before submitting again.");
            return existing.Id;
        }
        var c = new ServiceConcern { SubmissionKey = key, CustomerAccountId = account, RecordedById = who.Id, IntakeChannel = channel, Category = input.Category, Subject = subject, Description = description, Location = location, Contact = contact };
        db.Concerns.Add(c); await db.SaveChangesAsync(); // Sequence generates the reference safely across connections.
        db.ConcernEvents.Add(new() { ServiceConcernId = c.Id, ActorId = who.Id, At = c.SubmittedAt, Kind = "Receipt", NewState = ConcernState.Submitted, NewCategory = c.Category, Text = who.IsClient ? "Received — awaiting office review. Automatic receipt only; staff have not yet responded." : $"Received — awaiting office review. Recorded by office personnel through {ConcernLabels.Channel(channel)} on behalf of this account." });
        Audit(db, who, c.Id, "Concern received"); await db.SaveChangesAsync(); await tx.CommitAsync(); return c.Id;
    }
    public async Task<Page<ConcernRow>> ConcernsAsync(string search = "", ConcernCategory? category = null, ConcernState? state = null, int page = 1, Guid? accountId = null)
    {
        await using var db = await factory.CreateDbContextAsync(); var who = await Access.CurrentAsync(db, session);
        if (accountId.HasValue) Access.Account(who, accountId.Value);
        var q = Scope(db, who).AsNoTracking(); if (accountId.HasValue) q = q.Where(x => x.CustomerAccountId == accountId);
        if (!string.IsNullOrWhiteSpace(search)) { search = search.Trim().ToLowerInvariant(); q = q.Where(x => x.Subject.ToLower().Contains(search) || x.Reference.ToLower().Contains(search) || (who.Has(Permissions.ReadOffice) && x.CustomerAccount.Number.Contains(search))); }
        if (category.HasValue) q = q.Where(x => x.Category == category); if (state.HasValue) q = q.Where(x => x.State == state);
        var count = await q.CountAsync(); page = Math.Clamp(page, 1, Math.Max(1, (count + 19) / 20));
        var items = await q.Include(x => x.CustomerAccount).OrderByDescending(x => x.SubmittedAt).ThenBy(x => x.Id).Skip((page - 1) * 20).Take(20).ToArrayAsync();
        return new(items.Select(Row).ToArray(), count, page, 20);
    }
    public async Task<ConcernDetail> ConcernAsync(Guid id)
    {
        await using var db = await factory.CreateDbContextAsync(); var who = await Access.CurrentAsync(db, session);
        var c = await Scope(db, who).AsNoTracking().Include(x => x.CustomerAccount).Include(x => x.RecordedBy).SingleOrDefaultAsync(x => x.Id == id) ?? throw new BusinessException("Record unavailable for this account.");
        // Internal note bodies never enter a client DTO, even for manipulated detail identifiers.
        var events = await db.ConcernEvents.AsNoTracking().Where(x => x.ServiceConcernId == id && (!x.Internal || who.Has(Permissions.ReadOffice))).Include(x => x.Actor).OrderBy(x => x.At).ThenBy(x => x.Id).ToArrayAsync();
        return new(Row(c), c.CustomerAccountId, c.Description, c.Location, c.Contact, ConcernLabels.Channel(c.IntakeChannel), who.IsClient ? (c.IntakeChannel == IntakeChannel.DesktopClient ? "Account holder" : "Office personnel on behalf of account") : c.RecordedBy.DisplayName, c.FirstHumanResponseAt, null,
            events.Select(x => new TimelineRow(x.At, x.Kind, x.Text, x.Internal, who.IsClient ? (x.Kind == "Receipt" ? "Automatic receipt" : "Office personnel") : x.Actor.DisplayName, x.PreviousState, x.NewState)).ToArray());
    }
    public async Task ProcessConcernAsync(Guid id, Guid version, ConcernAction action, string text, ConcernCategory category)
    {
        text = ConcernPolicy.Meaningful(text);
        await using var db = await factory.CreateDbContextAsync(); var who = await Access.CurrentAsync(db, session);
        Access.Require(who, Permissions.ReadOffice); Access.Require(who, Permissions.Respond);
        await using var tx = await db.Database.BeginTransactionAsync();
        var c = await db.Concerns.Include(x => x.Ticket).SingleOrDefaultAsync(x => x.Id == id) ?? throw new BusinessException("Concern unavailable.");
        Fresh(c.Version, version); var oldState = c.State; var oldCategory = c.Category;
        c.State = ConcernPolicy.Next(c, action, category, text);
        if (action == ConcernAction.Reclassify) c.Category = category;
        var now = DateTimeOffset.UtcNow;
        if (action == ConcernAction.Respond) c.FirstHumanResponseAt ??= now;
        c.Version = Guid.NewGuid(); await db.SaveChangesAsync();
        var kind = action switch { ConcernAction.Respond => "Human response", ConcernAction.InternalNote => "Internal note", ConcernAction.Reclassify => "Classification corrected", _ => action.ToString() };
        db.ConcernEvents.Add(new() { ServiceConcernId = id, ActorId = who.Id, At = now, Kind = kind, Text = text, Internal = action is ConcernAction.InternalNote or ConcernAction.Reclassify or ConcernAction.Review, PreviousState = oldState, NewState = c.State, PreviousCategory = oldCategory, NewCategory = c.Category });
        Audit(db, who, id, "Concern " + action); await db.SaveChangesAsync(); await tx.CommitAsync();
    }
    // Compatibility entry point for preserved callers; still governed by the Phase 2 policy.
    public async Task RespondAsync(Guid id, Guid version, string response, bool internalNote, ConcernCategory category, bool complete)
        => await ProcessConcernAsync(id, version, internalNote ? ConcernAction.InternalNote : complete ? ConcernAction.Resolve : ConcernAction.Respond, response, category);
    public async Task<ConcernOverview> ConcernOverviewAsync()
    {
        await using var db = await factory.CreateDbContextAsync(); var who = await Access.CurrentAsync(db, session); var q = Scope(db, who).AsNoTracking();
        var recent = await q.Include(x => x.CustomerAccount).OrderByDescending(x => x.SubmittedAt).Take(5).ToArrayAsync();
        var pending = await q.Where(x => x.State == ConcernState.Submitted).Include(x => x.CustomerAccount).OrderBy(x => x.SubmittedAt).Take(4).ToArrayAsync();
        var activity = await db.ConcernEvents.AsNoTracking()
            .Where(x => q.Any(c => c.Id == x.ServiceConcernId) && (!x.Internal || who.Has(Permissions.ReadOffice)))
            .OrderByDescending(x => x.At).ThenBy(x => x.Id).Take(5)
            .Select(x => new ConcernActivity(x.ServiceConcernId, x.ServiceConcern.Reference,
                new TimelineRow(x.At, x.Kind, x.Text, x.Internal, who.IsClient ? (x.Kind == "Receipt" ? "Automatic receipt" : "Office personnel") : x.Actor.DisplayName, x.PreviousState, x.NewState)))
            .ToArrayAsync();
        return new(await q.CountAsync(), await q.CountAsync(x => x.State == ConcernState.Submitted), await q.CountAsync(x => x.State == ConcernState.UnderReview), await q.CountAsync(x => x.State == ConcernState.Closed), recent.Select(Row).ToArray(),
            await q.CountAsync(x => x.State == ConcernState.Resolved), activity, pending.Select(Row).ToArray());
    }
}
