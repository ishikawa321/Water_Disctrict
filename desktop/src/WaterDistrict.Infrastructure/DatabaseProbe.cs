using Npgsql;
using WaterDistrict.Application;

namespace WaterDistrict.Infrastructure;

public sealed class DatabaseProbe(string? connectionString)
{
    public async Task<DependencyStatus> CheckAsync(CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            return new("unconfigured", "Set the backend PostgreSQL connection to enable database workflows.");
        try
        {
            var settings = new NpgsqlConnectionStringBuilder(connectionString) { Timeout = 5, CommandTimeout = 5 };
            await using var connection = new NpgsqlConnection(settings.ConnectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new NpgsqlCommand("SELECT 1", connection);
            await command.ExecuteScalarAsync(cancellationToken);
            return new("ready", "PostgreSQL is reachable.");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception exception) when (exception is NpgsqlException or ArgumentException or InvalidOperationException)
        {
            return new("unavailable", "PostgreSQL could not be reached. Check backend configuration and connectivity.");
        }
    }
}
