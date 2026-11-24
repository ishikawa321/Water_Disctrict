using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using WaterDistrict.Api;
using WaterDistrict.Application;
using WaterDistrict.Infrastructure;

var builder = WebApplication.CreateBuilder(args);
builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true).AddEnvironmentVariables();
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<DependencyExceptionHandler>();
var supabase = builder.Configuration.GetSection("Supabase").Get<SupabaseOptions>() ?? new();
supabase.Validate();
builder.Services.AddSingleton(supabase);
builder.Services.AddHttpClient<IProfileReader, SupabaseProfileReader>(client =>
{
    client.BaseAddress = new Uri(supabase.Url.TrimEnd('/') + "/rest/v1/");
    client.DefaultRequestHeaders.Add("apikey", supabase.PublishableKey);
    client.Timeout = TimeSpan.FromSeconds(15);
});
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
{
    options.MapInboundClaims = false;
    options.IncludeErrorDetails = false;
    options.ConfigurationManager = new ConfigurationManager<OpenIdConnectConfiguration>(
        supabase.Issuer + "/.well-known/jwks.json",
        new SupabaseSigningKeysRetriever(supabase.Issuer), new HttpDocumentRetriever { RequireHttps = true });
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true, ValidIssuer = supabase.Issuer,
        ValidateAudience = true, ValidAudience = "authenticated",
        ValidateLifetime = true, RequireExpirationTime = true,
        RequireSignedTokens = true, ValidateIssuerSigningKey = true,
        ValidAlgorithms = [SecurityAlgorithms.EcdsaSha256, SecurityAlgorithms.RsaSha256],
        ClockSkew = TimeSpan.FromSeconds(30)
    };
});
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("Desktop", policy => policy.RequireAuthenticatedUser().AddRequirements(new ActiveDesktopProfileRequirement()));
    options.AddPolicy("Admin", policy => policy.RequireAuthenticatedUser().AddRequirements(new ActiveDesktopProfileRequirement(AdminOnly: true)));
});
builder.Services.AddScoped<IAuthorizationHandler, DesktopAuthorizationHandler>();
var connection = builder.Configuration.GetConnectionString("WaterDistrict");
builder.Services.AddSingleton(new DatabaseProbe(connection));
if (!string.IsNullOrWhiteSpace(connection))
    builder.Services.AddDbContext<WaterDistrictDbContext>(options => options.UseNpgsql(connection));
builder.Services.AddScoped<IWorkflowService>(services => string.IsNullOrWhiteSpace(connection)
    ? throw new DependencyUnavailableException("Configure the backend PostgreSQL connection before processing concerns or tickets.")
    : new WorkflowService(services.GetRequiredService<WaterDistrictDbContext>()));
var app = builder.Build();
app.UseExceptionHandler();
app.UseAuthentication();
app.UseAuthorization();
app.MapGet("/health", () => Results.Ok(new { status = "running", service = "Water District API" }));
app.MapGet("/health/ready", async (DatabaseProbe probe, CancellationToken token) =>
{
    var result = await probe.CheckAsync(token);
    return Results.Json(result, statusCode: result.Status == "ready" ? 200 : 503);
});
app.MapGet("/api/session", (HttpContext http) =>
    Results.Ok((SessionProfile)http.Items[DesktopAuthorizationHandler.SessionItem]!)).RequireAuthorization("Desktop");
app.MapGet("/api/admin/staff", async (HttpContext http, IProfileReader profiles, CancellationToken token) =>
{
    var bearer = http.Request.Headers.Authorization.ToString()[7..].Trim();
    var staff = await profiles.ListStaffAsync(bearer, token);
    return Results.Ok(staff.Where(profile => profile.Active && WaterDistrict.Domain.AppRoles.HasDesktopAccess(profile.Role))
        .Select(profile => new StaffMember(profile.UserId, profile.DisplayName, profile.Role)));
}).RequireAuthorization("Admin");
app.MapWorkflows();
app.Run();

public partial class Program;
