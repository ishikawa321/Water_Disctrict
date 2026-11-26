using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using WaterDistrictConnect.Core.Domain;
namespace WaterDistrictConnect.Core.Persistence;
public sealed record AppConfiguration(string? ConnectionString, bool DemoMode = false, bool SampleData = false, string? ConfigurationError = null)
{
    public static AppConfiguration Load()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "appsettings.local.json");
        AppConfiguration c;
        try { c = File.Exists(path) ? JsonSerializer.Deserialize<AppConfiguration>(File.ReadAllText(path), new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? new AppConfiguration((string?)null) : new AppConfiguration((string?)null); }
        catch (Exception e) when (e is JsonException or IOException or UnauthorizedAccessException)
        { c = new AppConfiguration(null, ConfigurationError: "Cannot read appsettings.local.json. Correct its JSON format and file access, then restart the application."); }
        return c with { ConnectionString = Environment.GetEnvironmentVariable("MWD_CONNECTION") ?? c.ConnectionString, DemoMode = Environment.GetEnvironmentVariable("MWD_DEMO") is string d ? d.Equals("true", StringComparison.OrdinalIgnoreCase) : c.DemoMode, SampleData = Environment.GetEnvironmentVariable("MWD_SAMPLE") is string s ? s.Equals("true", StringComparison.OrdinalIgnoreCase) : c.SampleData };
    }
    public void Validate()
    {
        if (ConfigurationError != null) throw new BusinessException(ConfigurationError);
        if (string.IsNullOrWhiteSpace(ConnectionString)) throw new BusinessException("PostgreSQL is not configured. Set MWD_CONNECTION or appsettings.local.json beside the executable. See README, then retry sign in.");
        try
        {
            var builder = new Npgsql.NpgsqlConnectionStringBuilder(ConnectionString);
            if (string.IsNullOrWhiteSpace(builder.Host) || string.IsNullOrWhiteSpace(builder.Database) || string.IsNullOrWhiteSpace(builder.Username))
                throw new ArgumentException();
        }
        catch (ArgumentException) { throw new BusinessException("PostgreSQL configuration is invalid. Supply Host, Database and Username in MWD_CONNECTION or appsettings.local.json, then restart. No alternate database is used."); }
    }
}
public sealed class DatabaseSetup(IDbContextFactory<WaterDbContext> factory, AppConfiguration configuration)
{
    public async Task CheckAsync()
    {
        configuration.Validate();
        await using var db = await factory.CreateDbContextAsync();
        if ((await db.Database.GetPendingMigrationsAsync()).Any()) throw new BusinessException("Database migrations are pending. Run WaterDistrictConnect.exe --migrate using your configured PostgreSQL database, then retry.");
        if (configuration.DemoMode) await DemoSeeder.SeedAsync(db, configuration.SampleData);
    }
    public async Task MigrateAsync()
    {
        configuration.Validate();
        await using var db = await factory.CreateDbContextAsync(); await db.Database.MigrateAsync();
        if (configuration.DemoMode) await DemoSeeder.SeedAsync(db, configuration.SampleData);
    }
}


