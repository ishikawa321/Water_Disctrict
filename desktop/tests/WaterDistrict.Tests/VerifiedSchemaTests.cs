using Microsoft.EntityFrameworkCore;
using Npgsql;
using WaterDistrict.Application;
using WaterDistrict.Infrastructure;

namespace WaterDistrict.Tests;

[Collection("Postgres")]
public sealed class VerifiedSchemaTests
{
    private static CancellationToken Token=>TestContext.Current.CancellationToken;
    private static async Task<T> AsCaller<T>(PostgresDatabase database,Guid user,string sql)
    {
        await using var connection=new NpgsqlConnection(database.Connection);await connection.OpenAsync(Token);
        await using var transaction=await connection.BeginTransactionAsync(Token);
        await using(var identity=new NpgsqlCommand($"SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','{user}',true)",connection,transaction))
            await identity.ExecuteNonQueryAsync(Token);
        await using var command=new NpgsqlCommand(sql,connection,transaction);
        var result=await command.ExecuteScalarAsync(Token);await transaction.CommitAsync(Token);return (T)result!;
    }
    [Fact]
    public async Task Reviewed_location_grant_allows_owned_consumer_pins_without_expanding_rls()
    {
        await using var database=await PostgresDatabase.CreateAsync(verifiedSchema:true);
        // Apply upstream SQL only inside this disposable fixture, never the operational project.
        await database.SqlAsync(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"add_concern_locations.sql"),Token));
        await database.SqlAsync(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"add_concern_locations.sql"),Token));
        var id=await AsCaller<Guid>(database,database.ClientId,$"INSERT INTO public.service_concerns(account_id,submitted_by,category,subject,description,latitude,longitude,location_note) VALUES('{database.AccountId}','{database.ClientId}','Water supply','Pinned concern','Test issue.',7.7633,125.0058,'Near test meter') RETURNING id");
        await using var db=database.Open(); var saved=await new WorkflowService(db).ConcernAsync(database.Admin,id,Token);
        Assert.Equal(7.7633,saved.Latitude); Assert.Equal(125.0058,saved.Longitude); Assert.Equal("Near test meter",saved.LocationNote);
        Assert.Equal(0,await AsCaller<int>(database,database.OtherClientId,"SELECT count(*)::int FROM public.service_concerns"));
        await Assert.ThrowsAsync<PostgresException>(()=>AsCaller<Guid>(database,database.ClientId,$"INSERT INTO public.service_concerns(account_id,submitted_by,category,subject,description,latitude,longitude) VALUES('{database.OtherAccountId}','{database.ClientId}','Water supply','Unauthorized pin','Other account.',7.76,125) RETURNING id"));
        await Assert.ThrowsAsync<PostgresException>(()=>AsCaller<Guid>(database,database.ClientId,$"INSERT INTO public.service_concerns(account_id,submitted_by,category,subject,description,latitude) VALUES('{database.AccountId}','{database.ClientId}','Water supply','Incomplete pin','Test issue.',7.76) RETURNING id"));
    }
    [Fact]
    public async Task Actual_schema_accepts_workflow_migrations_and_complete_staff_repair_processing()
    {
        await using var database=await PostgresDatabase.CreateAsync(verifiedSchema:true);
        await using var db=database.Open();var service=new WorkflowService(db);
        var concern=await service.CreateConcernAsync(database.Admin,new(Guid.NewGuid(),database.AccountId,"Repair request","Live-schema fixture","Test service connection requires repair."),Token);
        concern=await service.ReviewConcernAsync(database.Staff,concern.Id,new(concern.Version,"Under review","Checked for repair processing."),Token);
        var ticket=await service.CreateTicketAsync(database.Admin,new(concern.Id,concern.Version,"Dispatch verified repair."),Token);
        ticket=await service.UpdateTicketAsync(database.Admin,ticket.Ticket.Id,new(ticket.Ticket.Version,"Assigned",database.Staff.UserId,"Assigned active personnel."),Token);
        ticket=await service.UpdateTicketAsync(database.Staff,ticket.Ticket.Id,new(ticket.Ticket.Version,"In progress",database.Staff.UserId,"Repair started."),Token);
        ticket=await service.UpdateTicketAsync(database.Staff,ticket.Ticket.Id,new(ticket.Ticket.Version,"Resolved",database.Staff.UserId,"Repair completed."),Token);
        Assert.Equal(4,ticket.History.Count);Assert.Equal("Resolved",(await service.ConcernAsync(database.Admin,concern.Id,Token)).Status);
    }
    [Fact]
    public async Task Admin_can_read_staff_directory_but_staff_and_consumers_cannot_read_other_profiles()
    {
        await using var database=await PostgresDatabase.CreateAsync(verifiedSchema:true);
        Assert.Equal(2,await AsCaller<int>(database,database.Admin.UserId,"SELECT count(*)::int FROM public.profiles"));
        Assert.Equal(1,await AsCaller<int>(database,database.Staff.UserId,"SELECT count(*)::int FROM public.profiles"));
        Assert.Equal(1,await AsCaller<int>(database,database.ClientId,"SELECT count(*)::int FROM public.profiles"));
        await Assert.ThrowsAsync<PostgresException>(()=>AsCaller<int>(database,database.ClientId,"UPDATE public.profiles SET role='admin' RETURNING 1"));
    }
    [Fact]
    public async Task Existing_column_grants_support_notices_and_preserve_creator_and_consumer_isolation()
    {
        await using var database=await PostgresDatabase.CreateAsync(verifiedSchema:true);
        var id=await AsCaller<Guid>(database,database.Admin.UserId,$"INSERT INTO public.announcements(title,message,published,created_by,updated_by) VALUES('Test notice','Local verified schema test.',false,'{database.Admin.UserId}','{database.Admin.UserId}') RETURNING id");
        Assert.Equal(0,await AsCaller<int>(database,database.ClientId,"SELECT count(*)::int FROM public.announcements"));
        await AsCaller<bool>(database,database.Admin.UserId,$"UPDATE public.announcements SET published=true,updated_by='{database.Admin.UserId}' WHERE id='{id}' RETURNING published");
        Assert.Equal(1,await AsCaller<int>(database,database.ClientId,"SELECT count(*)::int FROM public.announcements"));
        await Assert.ThrowsAsync<PostgresException>(()=>AsCaller<int>(database,database.Admin.UserId,$"UPDATE public.announcements SET created_by='{database.ClientId}' WHERE id='{id}' RETURNING 1"));
        await Assert.ThrowsAsync<PostgresException>(()=>AsCaller<Guid>(database,database.Staff.UserId,$"INSERT INTO public.announcements(title,message,published,created_by,updated_by) VALUES('Denied','Staff is not Admin.',true,'{database.Staff.UserId}','{database.Staff.UserId}') RETURNING id"));
    }
    [Fact]
    public async Task Consumer_submission_works_with_actual_column_grants_and_cannot_read_other_accounts()
    {
        await using var database=await PostgresDatabase.CreateAsync(verifiedSchema:true);
        var id=await AsCaller<Guid>(database,database.ClientId,$"INSERT INTO public.service_concerns(account_id,submitted_by,category,subject,description) VALUES('{database.AccountId}','{database.ClientId}','Water supply','Consumer report','No water at the service address.') RETURNING id");
        await using var db=database.Open();var incoming=await new WorkflowService(db).ConcernAsync(database.Admin,id,Token);
        Assert.Equal("Consumer report",incoming.Subject);
        Assert.Equal(0,await AsCaller<int>(database,database.OtherClientId,"SELECT count(*)::int FROM public.service_concerns"));
        await Assert.ThrowsAsync<PostgresException>(()=>AsCaller<Guid>(database,database.ClientId,$"INSERT INTO public.service_concerns(account_id,submitted_by,category,subject,description) VALUES('{database.OtherAccountId}','{database.ClientId}','Water supply','Unauthorized','Cannot submit for another account.') RETURNING id"));
    }
    [Fact]
    public async Task Subject_exceeding_live_150_character_limit_is_rejected_without_saving()
    {
        await using var database=await PostgresDatabase.CreateAsync(verifiedSchema:true);
        await using var db=database.Open();
        var failure=await Assert.ThrowsAsync<WaterDistrict.Domain.WorkflowException>(()=>new WorkflowService(db).CreateConcernAsync(database.Admin,
            new(Guid.NewGuid(),database.AccountId,"Repair request",new string('s',151),"Description within the actual schema limit."),Token));
        Assert.Equal("validation",failure.Code);Assert.Empty(await db.Concerns.ToListAsync(Token));
    }

}
