using Microsoft.EntityFrameworkCore;
using WaterDistrict.Infrastructure;

var builder = WebApplication.CreateBuilder(args);
builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true).AddEnvironmentVariables();
builder.Services.AddProblemDetails();
var connection = builder.Configuration.GetConnectionString("WaterDistrict");
builder.Services.AddSingleton(new DatabaseProbe(connection));
if (!string.IsNullOrWhiteSpace(connection))
    builder.Services.AddDbContext<WaterDistrictDbContext>(options => options.UseNpgsql(connection));
var app = builder.Build();
app.UseExceptionHandler();
app.MapGet("/health", () => Results.Ok(new { status = "running", service = "Water District API" }));
app.MapGet("/health/ready", async (DatabaseProbe probe, CancellationToken token) =>
{
    var result = await probe.CheckAsync(token);
    return Results.Json(result, statusCode: result.Status == "ready" ? 200 : 503);
});
app.Run();

public partial class Program;
