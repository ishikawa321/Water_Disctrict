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
            await using var schema = new NpgsqlCommand("""
                SELECT to_regclass('public.ticket_status_history') IS NOT NULL
                 AND EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='repair_tickets' AND column_name='assigned_to_user_id')
                 AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='wd_ticket_event' AND tgenabled <> 'D')
                """, connection);
            if (await schema.ExecuteScalarAsync(cancellationToken) is not true)
                return new("setup_required", "PostgreSQL is reachable. Apply the reviewed workflow migration before processing records.");
            return new("ready", "PostgreSQL is reachable.");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception exception) when (exception is NpgsqlException or ArgumentException or InvalidOperationException)
        {
            return new("unavailable", "PostgreSQL could not be reached. Check backend configuration and connectivity.");
        }
    }
}
