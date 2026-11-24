using Microsoft.EntityFrameworkCore;
using Npgsql;
using WaterDistrict.Application;
using WaterDistrict.Domain;
using WaterDistrict.Infrastructure;

namespace WaterDistrict.Tests;

public sealed class PostgresDatabase : IAsyncDisposable
{
    private readonly string adminConnection;
    private readonly string name;
    public string Connection { get; }
    public SessionProfile Admin { get; } = new(Guid.NewGuid(), "Admin test", "admin", []);
    public SessionProfile Staff { get; } = new(Guid.NewGuid(), "Staff test", "staff", []);
    public Guid ClientId { get; } = Guid.NewGuid();
    public Guid OtherClientId { get; } = Guid.NewGuid();
    public Guid AccountId { get; } = Guid.NewGuid();
    public Guid OtherAccountId { get; } = Guid.NewGuid();
    private PostgresDatabase(string connection)
    {
        var settings = new NpgsqlConnectionStringBuilder(connection);
        if (settings.Host is not ("127.0.0.1" or "localhost")) throw new InvalidOperationException("Integration tests require a loopback PostgreSQL server.");
        settings.Database = "postgres";
        adminConnection = settings.ConnectionString;
        name = "waterdistrict_test_" + Guid.NewGuid().ToString("N");
        settings.Database = name;
        Connection = settings.ConnectionString;
    }
    public static async Task<PostgresDatabase> CreateAsync()
    {
        var connection = Environment.GetEnvironmentVariable("WATERDISTRICT_TEST_POSTGRES");
        Assert.SkipWhen(string.IsNullOrWhiteSpace(connection), "Set WATERDISTRICT_TEST_POSTGRES to a local disposable PostgreSQL server.");
        var database = new PostgresDatabase(connection!);
        await using var admin = new NpgsqlConnection(database.adminConnection);
        await admin.OpenAsync(TestContext.Current.CancellationToken);
        await using (var create = new NpgsqlCommand($"CREATE DATABASE {database.name}", admin)) await create.ExecuteNonQueryAsync(TestContext.Current.CancellationToken);
        try
        {
            await database.SqlAsync(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "development-baseline.sql"), TestContext.Current.CancellationToken));
            await using var db = database.Open();
            await db.Database.MigrateAsync(TestContext.Current.CancellationToken);
            db.Profiles.AddRange(new AppProfile { UserId=database.Admin.UserId, DisplayName=database.Admin.DisplayName, Role="admin", Active=true },
                new AppProfile { UserId=database.Staff.UserId, DisplayName=database.Staff.DisplayName, Role="staff", Active=true },
                new AppProfile { UserId=database.ClientId, DisplayName="Consumer test", Role="client", Active=true },
                new AppProfile { UserId=database.OtherClientId, DisplayName="Other consumer", Role="client", Active=true });
            db.Accounts.AddRange(new ServiceAccount { Id=database.AccountId, AccountNumber="TEST-001", HolderName="Consumer test", ServiceAddress="Test address", Active=true },
                new ServiceAccount { Id=database.OtherAccountId, AccountNumber="TEST-002", HolderName="Other consumer", ServiceAddress="Other address", Active=true });
            await db.SaveChangesAsync(TestContext.Current.CancellationToken);
            await database.SqlAsync($"INSERT INTO public.account_access(user_id,account_id) VALUES('{database.ClientId}','{database.AccountId}'),('{database.OtherClientId}','{database.OtherAccountId}')");
            return database;
        }
        catch { await database.DisposeAsync(); throw; }
    }
    public WaterDistrictDbContext Open() => new(new DbContextOptionsBuilder<WaterDistrictDbContext>().UseNpgsql(Connection).Options);
    public async Task SqlAsync(string sql)
    {
        await using var connection = new NpgsqlConnection(Connection);
        await connection.OpenAsync(TestContext.Current.CancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await command.ExecuteNonQueryAsync(TestContext.Current.CancellationToken);
    }
    public async ValueTask DisposeAsync()
    {
        NpgsqlConnection.ClearAllPools();
        await using var admin = new NpgsqlConnection(adminConnection);
        await admin.OpenAsync();
        await using var drop = new NpgsqlCommand($"DROP DATABASE IF EXISTS {name} WITH (FORCE)", admin);
        await drop.ExecuteNonQueryAsync();
    }
}
[CollectionDefinition("Postgres", DisableParallelization = true)] public sealed class PostgresCollection;
