using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using WaterDistrict.Application;
using WaterDistrict.Domain;
using WaterDistrict.Infrastructure;

namespace WaterDistrict.Tests;

[Collection("Postgres")]
public sealed class WorkflowApiTests
{
    private static CancellationToken Token=>TestContext.Current.CancellationToken;
    [Fact]
    public async Task Api_transports_the_intake_review_dispatch_and_resolution_workflows()
    {
        await using var database=await PostgresDatabase.CreateAsync();await using var app=new Factory(database.Connection);
        using var admin=app.Caller(database.Admin.UserId);
        var accounts=await admin.GetFromJsonAsync<AccountOption[]>("/api/workflow/accounts?search=TEST-001",Token);Assert.Single(accounts!);
        var intake=await admin.PostAsJsonAsync("/api/workflow/concerns",new CreateConcern(Guid.NewGuid(),database.AccountId,"Repair request","API repair report","Service connection is leaking."),Token);
        intake.EnsureSuccessStatusCode();var concern=(await intake.Content.ReadFromJsonAsync<ConcernRecord>(Token))!;
        var reviewed=await admin.PutAsJsonAsync($"/api/workflow/concerns/{concern.Id}/review",new ReviewConcern(concern.Version,"Under review","Reviewed for dispatch."),Token);
        reviewed.EnsureSuccessStatusCode();concern=(await reviewed.Content.ReadFromJsonAsync<ConcernRecord>(Token))!;
        var created=await admin.PostAsJsonAsync("/api/workflow/tickets",new CreateTicket(concern.Id,concern.Version,"Dispatch required."),Token);
        created.EnsureSuccessStatusCode();var ticket=(await created.Content.ReadFromJsonAsync<TicketDetails>(Token))!;
        var assigned=await admin.PutAsJsonAsync($"/api/workflow/tickets/{ticket.Ticket.Id}",new UpdateTicket(ticket.Ticket.Version,"Assigned",database.Staff.UserId,"Assigned to repair staff."),Token);
        assigned.EnsureSuccessStatusCode();ticket=(await assigned.Content.ReadFromJsonAsync<TicketDetails>(Token))!;
        using var staff=app.Caller(database.Staff.UserId);
        foreach(var status in new[]{"In progress","Resolved"})
        {
            var response=await staff.PutAsJsonAsync($"/api/workflow/tickets/{ticket.Ticket.Id}",new UpdateTicket(ticket.Ticket.Version,status,database.Staff.UserId,"Verified repair update: "+status),Token);
            response.EnsureSuccessStatusCode();ticket=(await response.Content.ReadFromJsonAsync<TicketDetails>(Token))!;
        }
        Assert.Equal(4,ticket.History.Count);
        var listed=await staff.GetFromJsonAsync<TicketRecord[]>("/api/workflow/tickets?status=Resolved&search=API",Token);Assert.Single(listed!);
        var concerns=await admin.GetFromJsonAsync<ConcernRecord[]>("/api/workflow/concerns?status=Resolved",Token);Assert.Single(concerns!);
        Assert.Equal(ticket.Ticket.LatestUpdate,concerns![0].Response);
        var health=await new DatabaseProbe(database.Connection).CheckAsync(Token);Assert.Equal("ready",health.Status);
    }
    [Fact]
    public async Task Api_returns_rule_failures_and_refuses_consumers_and_staff_dispatch()
    {
        await using var database=await PostgresDatabase.CreateAsync();await using var app=new Factory(database.Connection);
        using var admin=app.Caller(database.Admin.UserId);
        var invalid=await admin.PostAsJsonAsync("/api/workflow/concerns",new CreateConcern(Guid.NewGuid(),database.AccountId,"Repair request","",""),Token);
        Assert.Equal(HttpStatusCode.UnprocessableEntity,invalid.StatusCode);Assert.Contains("required",await invalid.Content.ReadAsStringAsync(Token));
        using var staff=app.Caller(database.Staff.UserId);
        var forbidden=await staff.PostAsJsonAsync("/api/workflow/tickets",new CreateTicket(Guid.NewGuid(),1,"Not authorized."),Token);
        Assert.Equal(HttpStatusCode.Forbidden,forbidden.StatusCode);
        using var consumer=app.Caller(database.ClientId);
        Assert.Equal(HttpStatusCode.Forbidden,(await consumer.GetAsync("/api/workflow/concerns",Token)).StatusCode);
        using var anonymous=app.CreateClient();Assert.Equal(HttpStatusCode.Unauthorized,(await anonymous.GetAsync("/api/workflow/tickets",Token)).StatusCode);
    }
    private sealed class Factory(string connection):WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)=>builder.ConfigureServices(services=>
        {
            services.RemoveAll<WaterDistrictDbContext>();services.RemoveAll<DbContextOptions<WaterDistrictDbContext>>();
            services.AddDbContext<WaterDistrictDbContext>(options=>options.UseNpgsql(connection));
            services.RemoveAll<IWorkflowService>();services.AddScoped<IWorkflowService,WorkflowService>();
            services.RemoveAll<IProfileReader>();services.AddScoped<IProfileReader,TestProfiles>();
            services.AddAuthentication(options=>{options.DefaultAuthenticateScheme="ControlledIdentity";options.DefaultChallengeScheme="ControlledIdentity";options.DefaultForbidScheme="ControlledIdentity";})
                .AddScheme<AuthenticationSchemeOptions,IdentityHandler>("ControlledIdentity",_=>{});
        });
        public HttpClient Caller(Guid user)
        { var client=CreateClient();client.DefaultRequestHeaders.Add("X-Test-User",user.ToString());client.DefaultRequestHeaders.Authorization=new AuthenticationHeaderValue("Bearer","controlled-test-token");return client; }
    }
    // Test-host identity control only. Production JWT cryptography is covered by AuthorizationTests.
    private sealed class IdentityHandler(IOptionsMonitor<AuthenticationSchemeOptions> options,ILoggerFactory logger,UrlEncoder encoder):AuthenticationHandler<AuthenticationSchemeOptions>(options,logger,encoder)
    {
        protected override Task<AuthenticateResult> HandleAuthenticateAsync()=>Task.FromResult(Guid.TryParse(Request.Headers["X-Test-User"],out var id)
            ? AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(new ClaimsIdentity([new Claim("sub",id.ToString())],Scheme.Name)),Scheme.Name))
            : AuthenticateResult.NoResult());
    }
    private sealed class TestProfiles(WaterDistrictDbContext db):IProfileReader
    {
        public Task<AppProfile?> FindAsync(Guid userId,string bearerToken,CancellationToken cancellationToken)=>db.Profiles.AsNoTracking().SingleOrDefaultAsync(row=>row.UserId==userId,cancellationToken);
        public async Task<IReadOnlyList<AppProfile>> ListStaffAsync(string bearerToken,CancellationToken cancellationToken)=>await db.Profiles.AsNoTracking().ToListAsync(cancellationToken);
    }
}
