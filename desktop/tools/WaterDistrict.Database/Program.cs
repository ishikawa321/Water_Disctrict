using System.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using WaterDistrict.Infrastructure;

var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__WaterDistrict");
if (string.IsNullOrWhiteSpace(connectionString))
{
    Console.Error.WriteLine("Set ConnectionStrings__WaterDistrict locally. No database was contacted.");
    return 2;
}
var mode=args.Length==0?"--inspect":args[0];
if(mode is not ("--inspect" or "--migrate" or "--bootstrap-development"))
{
    Console.Error.WriteLine("Use --inspect (default), --migrate, or --bootstrap-development.");return 2;
}
try
{
    if(mode=="--bootstrap-development")
    {
        var settings=new NpgsqlConnectionStringBuilder(connectionString);
        if(settings.Host is not ("127.0.0.1" or "localhost") || settings.Database is null ||
            !settings.Database.StartsWith("waterdistrict_dev",StringComparison.Ordinal) ||
            settings.Database.Any(character=>!char.IsAsciiLetterOrDigit(character) && character!='_'))
            throw new InvalidOperationException("Development bootstrap requires a loopback server and a database named waterdistrict_dev... .");
        var databaseName=settings.Database;settings.Database="postgres";
        await using(var admin=new NpgsqlConnection(settings.ConnectionString))
        {
            await admin.OpenAsync();
            await using var exists=new NpgsqlCommand("SELECT 1 FROM pg_database WHERE datname=@name",admin);
            exists.Parameters.AddWithValue("name",databaseName);
            if(await exists.ExecuteScalarAsync() is null)
            {
                await using var create=new NpgsqlCommand($"CREATE DATABASE {databaseName}",admin);
                await create.ExecuteNonQueryAsync();
            }
        }
        await using(var connection=new NpgsqlConnection(connectionString))
        {
            await connection.OpenAsync();
            await using var exists=new NpgsqlCommand("SELECT to_regclass('public.profiles') IS NOT NULL",connection);
            if(await exists.ExecuteScalarAsync() is true)
                throw new InvalidOperationException("This database is already initialized. Use --migrate; bootstrap never resets records.");
            await using var transaction=await connection.BeginTransactionAsync();
            var baseline=await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"development-baseline.sql"));
            await using var initialize=new NpgsqlCommand(baseline,connection,transaction);
            await initialize.ExecuteNonQueryAsync();await transaction.CommitAsync();
        }
    }
    if(mode is "--migrate" or "--bootstrap-development")
    {
        await using var db=new WaterDistrictDbContext(new DbContextOptionsBuilder<WaterDistrictDbContext>().UseNpgsql(connectionString).Options);
        await db.Database.MigrateAsync();
        Console.WriteLine("Reviewed workflow migrations applied. No operational seed records were added.");return 0;
    }
    await using var inspectionConnection=new NpgsqlConnection(connectionString);await inspectionConnection.OpenAsync();
    await using var readTransaction=await inspectionConnection.BeginTransactionAsync(IsolationLevel.RepeatableRead);
    await using(var readOnly=new NpgsqlCommand("SET TRANSACTION READ ONLY",inspectionConnection,readTransaction)) await readOnly.ExecuteNonQueryAsync();
    var sql=await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"inspect.sql"));
    await using var command=new NpgsqlCommand(sql,inspectionConnection,readTransaction){CommandTimeout=30};
    Console.WriteLine(await command.ExecuteScalarAsync());await readTransaction.RollbackAsync();return 0;
}
catch(InvalidOperationException exception)
{ Console.Error.WriteLine(exception.Message);return 1; }
catch(Exception exception) when(exception is NpgsqlException or ArgumentException or IOException)
{
    Console.Error.WriteLine("Database operation failed. Check connectivity and inspect the schema before migrating. No success is claimed.");
    if(exception is PostgresException pg)
    {
        Console.Error.WriteLine("PostgreSQL SQLSTATE: " + pg.SqlState);
        if(pg.SqlState=="28P01") Console.Error.WriteLine("Database authentication failed. Confirm the Supabase database password and pooler username in local configuration.");
        else if(pg.SqlState=="42501") Console.Error.WriteLine("The database user does not have permission for this operation.");
        else if(pg.SqlState=="P0001") Console.Error.WriteLine(pg.MessageText);
    }
    else
    {
        Console.Error.WriteLine("Failure type: " + exception.GetType().Name + (exception.InnerException is null ? "" : "/" + exception.InnerException.GetType().Name));
        if(exception.InnerException is System.Security.Authentication.AuthenticationException tls)
            Console.Error.WriteLine("TLS validation: " + tls.Message);
    }
    return 1;
}
