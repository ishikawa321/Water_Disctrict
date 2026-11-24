using Microsoft.EntityFrameworkCore;
using Npgsql;
using WaterDistrict.Application;
using WaterDistrict.Domain;
using WaterDistrict.Infrastructure;

namespace WaterDistrict.Tests;

[Collection("Postgres")]
public sealed class WorkflowIntegrationTests
{
    private static CancellationToken Token => TestContext.Current.CancellationToken;
    private static CreateConcern Intake(PostgresDatabase database, Guid? id = null) => new(id ?? Guid.NewGuid(), database.AccountId, "Repair request", "Leak at service line", "Visible leak reported at the service connection.");
    private static async Task<ConcernRecord> Reviewed(PostgresDatabase database)
    {
        await using var db = database.Open();
        var service = new WorkflowService(db);
        var concern = await service.CreateConcernAsync(database.Admin, Intake(database), Token);
        return await service.ReviewConcernAsync(database.Admin, concern.Id, new(concern.Version, "Under review", "Repair required after office review."), Token);
    }

    [Fact]
    public async Task Intake_is_durable_and_retrying_the_same_request_is_idempotent()
    {
        await using var database = await PostgresDatabase.CreateAsync();
        var input = Intake(database);
        await using (var db = database.Open())
        {
            var service = new WorkflowService(db);
            var created = await service.CreateConcernAsync(database.Admin, input, Token);
            Assert.True(created.Version > 0);
            Assert.Equal(input.RequestId, (await service.CreateConcernAsync(database.Admin, input, Token)).Id);
        }
        await using var fresh = database.Open();
        Assert.Equal(1, await fresh.Concerns.CountAsync(Token));
        var saved = await fresh.Concerns.SingleAsync(Token);
        Assert.Equal("Submitted", saved.Status);
        Assert.Equal(database.AccountId, saved.AccountId);
        Assert.Equal(database.Admin.UserId, saved.SubmittedBy);
    }

    [Fact]
    public async Task Invalid_information_or_account_is_rejected_without_records()
    {
        await using var database = await PostgresDatabase.CreateAsync();
        await using var db = database.Open(); var service = new WorkflowService(db);
        await Assert.ThrowsAsync<WorkflowException>(() => service.CreateConcernAsync(database.Admin, Intake(database) with { Description="" }, Token));
        await Assert.ThrowsAsync<WorkflowException>(() => service.CreateConcernAsync(database.Admin, Intake(database) with { AccountId=Guid.NewGuid() }, Token));
        Assert.Empty(await db.Concerns.ToListAsync(Token));
    }

    [Fact]
    public async Task Billing_question_can_close_with_response_without_a_ticket()
    {
        await using var database = await PostgresDatabase.CreateAsync();
        await using var db = database.Open(); var service = new WorkflowService(db);
        var concern = await service.CreateConcernAsync(database.Staff, Intake(database) with { Category="Billing inquiry" }, Token);
        await Assert.ThrowsAsync<WorkflowException>(() => service.ReviewConcernAsync(database.Staff, concern.Id, new(concern.Version,"Closed",""), Token));
        var closed = await service.ReviewConcernAsync(database.Staff, concern.Id, new(concern.Version,"Closed","Explained the billing period using district records."), Token);
        Assert.Equal("Closed", closed.Status); Assert.Null(closed.TicketId); Assert.NotNull(closed.ReviewedAt);
        Assert.Empty(await db.Tickets.ToListAsync(Token));
    }

    [Fact]
    public async Task Ticket_assignment_and_resolution_preserve_history_and_consumer_summary()
    {
        await using var database = await PostgresDatabase.CreateAsync();
        var concern = await Reviewed(database);
        await using var db = database.Open(); var service = new WorkflowService(db);
        var opened = await service.CreateTicketAsync(database.Admin, new(concern.Id,concern.Version,"Office approved repair dispatch."), Token);
        Assert.Single(opened.History); Assert.Equal("Open", opened.History[0].Status);
        Assert.NotNull((await db.Concerns.AsNoTracking().SingleAsync(Token)).RepairDispatchedAt);
        var assigned = await service.UpdateTicketAsync(database.Admin, opened.Ticket.Id, new(opened.Ticket.Version,"Assigned",database.Staff.UserId,"Assigned to repair staff."), Token);
        Assert.Equal(database.Staff.DisplayName, assigned.Ticket.AssignedTo);
        var progress = await service.UpdateTicketAsync(database.Staff, assigned.Ticket.Id, new(assigned.Ticket.Version,"In progress",database.Staff.UserId,"Repair work started after inspection."), Token);
        var resolved = await service.UpdateTicketAsync(database.Staff, progress.Ticket.Id, new(progress.Ticket.Version,"Resolved",database.Staff.UserId,"Repair completed and outcome verified by staff."), Token);
        Assert.Equal(new[] {"Open","Assigned","In progress","Resolved"}, resolved.History.Select(row=>row.Status));
        await using var fresh = database.Open();
        var persisted = await fresh.Concerns.SingleAsync(Token);
        Assert.Equal("Resolved", persisted.Status);
        Assert.Equal(resolved.Ticket.LatestUpdate, persisted.AdminResponse);
        Assert.Equal(database.Staff.UserId, persisted.ReviewedBy);
        Assert.Equal(4, await fresh.History.CountAsync(Token));
    }

    [Fact]
    public async Task Failure_after_history_insert_rolls_back_ticket_history_and_dispatch_marker()
    {
        await using var database = await PostgresDatabase.CreateAsync();
        var concern = await Reviewed(database);
        await database.SqlAsync("""
            CREATE FUNCTION public.test_fail_dispatch() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN IF NEW.repair_dispatched_at IS NOT NULL THEN RAISE EXCEPTION 'Controlled essential write failure'; END IF; RETURN NEW; END $$;
            CREATE TRIGGER test_fail_dispatch BEFORE UPDATE ON public.service_concerns FOR EACH ROW EXECUTE FUNCTION public.test_fail_dispatch();
            """);
        await using (var db = database.Open())
            await Assert.ThrowsAsync<DbUpdateException>(() => new WorkflowService(db).CreateTicketAsync(database.Admin, new(concern.Id,concern.Version,"Dispatch should roll back."), Token));
        await using var fresh = database.Open();
        Assert.Empty(await fresh.Tickets.ToListAsync(Token)); Assert.Empty(await fresh.History.ToListAsync(Token));
        var original = await fresh.Concerns.SingleAsync(Token);
        Assert.Null(original.RepairDispatchedAt); Assert.Equal("Under review", original.Status);
    }

    [Fact]
    public async Task Concurrent_creators_leave_one_ticket_and_one_initial_event()
    {
        await using var database = await PostgresDatabase.CreateAsync(); var concern=await Reviewed(database);
        async Task<bool> Attempt()
        {
            await using var db=database.Open();
            try { await new WorkflowService(db).CreateTicketAsync(database.Admin,new(concern.Id,concern.Version,"Dispatch request."),Token); return true; }
            catch(WorkflowException exception) { Assert.Equal(409,exception.StatusCode); return false; }
        }
        var results=await Task.WhenAll(Attempt(),Attempt()); Assert.Single(results,result=>result);
        await using var fresh=database.Open(); Assert.Equal(1,await fresh.Tickets.CountAsync(Token)); Assert.Equal(1,await fresh.History.CountAsync(Token));
    }

    [Fact]
    public async Task Stale_review_cannot_overwrite_the_saved_decision()
    {
        await using var database=await PostgresDatabase.CreateAsync();
        ConcernRecord original;
        await using(var db=database.Open()) original=await new WorkflowService(db).CreateConcernAsync(database.Admin,Intake(database),Token);
        await using(var db=database.Open()) await new WorkflowService(db).ReviewConcernAsync(database.Admin,original.Id,new(original.Version,"Under review","First review."),Token);
        await using(var db=database.Open())
        {
            var failure=await Assert.ThrowsAsync<WorkflowException>(()=>new WorkflowService(db).ReviewConcernAsync(database.Admin,original.Id,new(original.Version,"Closed","Stale closure."),Token));
            Assert.Equal(409,failure.StatusCode);
        }
        await using var fresh=database.Open(); Assert.Equal("First review.",(await fresh.Concerns.SingleAsync(Token)).AdminResponse);
    }

    [Fact]
    public async Task Invalid_transition_inactive_assignee_and_unassigned_staff_change_nothing()
    {
        await using var database=await PostgresDatabase.CreateAsync();var concern=await Reviewed(database);
        await using var db=database.Open();var service=new WorkflowService(db);
        var ticket=await service.CreateTicketAsync(database.Admin,new(concern.Id,concern.Version,"Dispatch request."),Token);
        await Assert.ThrowsAsync<WorkflowException>(()=>service.UpdateTicketAsync(database.Admin,ticket.Ticket.Id,new(ticket.Ticket.Version,"Resolved",database.Staff.UserId,"Skip progress."),Token));
        await database.SqlAsync($"UPDATE public.profiles SET active=false WHERE user_id='{database.Staff.UserId}'");
        await Assert.ThrowsAsync<WorkflowException>(()=>service.UpdateTicketAsync(database.Admin,ticket.Ticket.Id,new(ticket.Ticket.Version,"Assigned",database.Staff.UserId,"Inactive assignee."),Token));
        await database.SqlAsync($"UPDATE public.profiles SET active=true WHERE user_id='{database.Staff.UserId}'");
        await Assert.ThrowsAsync<WorkflowException>(()=>service.TicketAsync(database.Staff,ticket.Ticket.Id,Token));
        var denied=await Assert.ThrowsAsync<WorkflowException>(()=>service.UpdateTicketAsync(database.Staff,ticket.Ticket.Id,new(ticket.Ticket.Version,"Assigned",database.Staff.UserId,"Self assign."),Token));
        Assert.Equal(403,denied.StatusCode);
        Assert.Single(await db.History.ToListAsync(Token));
    }

    [Fact]
    public async Task Consumer_rls_hides_other_accounts_and_prevents_profile_escalation()
    {
        await using var database=await PostgresDatabase.CreateAsync();var concern=await Reviewed(database);
        await using(var db=database.Open()) await new WorkflowService(db).CreateTicketAsync(database.Admin,new(concern.Id,concern.Version,"Dispatch request."),Token);
        async Task<int> VisibleHistory(Guid user)
        {
            await using var connection=new NpgsqlConnection(database.Connection);await connection.OpenAsync(Token);
            await using var transaction=await connection.BeginTransactionAsync(Token);
            await using(var identity=new NpgsqlCommand($"SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','{user}',true)",connection,transaction)) await identity.ExecuteNonQueryAsync(Token);
            await using var read=new NpgsqlCommand("SELECT count(*)::int FROM public.ticket_status_history",connection,transaction);
            return (int)(await read.ExecuteScalarAsync(Token))!;
        }
        Assert.Equal(1,await VisibleHistory(database.ClientId)); Assert.Equal(0,await VisibleHistory(database.OtherClientId));
        await using var caller=new NpgsqlConnection(database.Connection);await caller.OpenAsync(Token);
        await using var tx=await caller.BeginTransactionAsync(Token);
        await using(var role=new NpgsqlCommand($"SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','{database.ClientId}',true)",caller,tx)) await role.ExecuteNonQueryAsync(Token);
        await using var elevate=new NpgsqlCommand("UPDATE public.profiles SET role='admin'",caller,tx);
        var rejected=await Assert.ThrowsAsync<PostgresException>(()=>elevate.ExecuteNonQueryAsync(Token)); Assert.Equal("42501",rejected.SqlState);
    }

    [Fact]
    public async Task Consumer_submission_enters_desktop_processing_with_server_recorded_identity()
    {
        await using var database=await PostgresDatabase.CreateAsync();var id=Guid.NewGuid();
        await using(var connection=new NpgsqlConnection(database.Connection))
        {
            await connection.OpenAsync(Token);await using var transaction=await connection.BeginTransactionAsync(Token);
            await using var command=new NpgsqlCommand($"""
              SET LOCAL ROLE authenticated;
              SELECT set_config('request.jwt.claim.sub','{database.ClientId}',true);
              INSERT INTO public.service_concerns(id,account_id,submitted_by,category,subject,description)
              VALUES('{id}','{database.AccountId}','{database.Admin.UserId}','Water supply','Consumer submission','No water since this morning.');
              """,connection,transaction);
            await command.ExecuteNonQueryAsync(Token);await transaction.CommitAsync(Token);
        }
        await using var db=database.Open();var service=new WorkflowService(db);
        var incoming=await service.ConcernAsync(database.Staff,id,Token);
        Assert.Equal("Consumer submission",incoming.Subject);
        Assert.Equal(database.ClientId,(await db.Concerns.SingleAsync(Token)).SubmittedBy);
        var review=await service.ReviewConcernAsync(database.Staff,id,new(incoming.Version,"Under review","Received for repair assessment."),Token);
        Assert.Equal("Under review",review.Status);
    }
    [Fact]
    public async Task Missing_migration_prevents_workflow_processing_without_partial_records()
    {
        await using var database=await PostgresDatabase.CreateAsync();
        await database.SqlAsync("DELETE FROM public.\"__EFMigrationsHistory\"");
        await using var db=database.Open();
        var rejected=await Assert.ThrowsAsync<DependencyUnavailableException>(()=>new WorkflowService(db).CreateConcernAsync(database.Admin,Intake(database),Token));
        Assert.Contains("migration",rejected.Message);
        Assert.Empty(await db.Concerns.ToListAsync(Token));
    }

}
