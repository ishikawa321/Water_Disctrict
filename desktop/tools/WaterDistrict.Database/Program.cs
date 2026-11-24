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
if(mode is not ("--inspect" or "--migrate" or "--bootstrap-development" or "--export-schema" or "--backup-public" or "--status"))
{
    Console.Error.WriteLine("Use --inspect (default), --status, --export-schema, --backup-public FILE, --migrate, or --bootstrap-development.");return 2;
}
try
{
    if(mode is "--export-schema" or "--backup-public")
    {
        var settings=new NpgsqlConnectionStringBuilder(connectionString);
        var start=new System.Diagnostics.ProcessStartInfo(Environment.GetEnvironmentVariable("PG_DUMP_PATH")??"pg_dump")
        { UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true };
        foreach(var argument in new[]{"--schema=public","--no-owner","--lock-wait-timeout=10s"})start.ArgumentList.Add(argument);
        if(mode=="--backup-public")
        {
            if(args.Length!=2)throw new InvalidOperationException("Specify a new local backup file path.");
            var backupPath=Path.GetFullPath(args[1]);
            if(File.Exists(backupPath))throw new InvalidOperationException("Backup output already exists; choose a new filename.");
            start.ArgumentList.Add("--format=custom");start.ArgumentList.Add("--file="+backupPath);
        }
        else start.ArgumentList.Add("--schema-only");
        start.Environment["PGHOST"]=settings.Host;start.Environment["PGPORT"]=settings.Port.ToString();
        start.Environment["PGDATABASE"]=settings.Database;start.Environment["PGUSER"]=settings.Username;
        start.Environment["PGPASSWORD"]=settings.Password;start.Environment["PGCONNECT_TIMEOUT"]="10";
        start.Environment["PGSSLMODE"]=settings.SslMode==SslMode.VerifyFull?"verify-full":settings.SslMode==SslMode.Require?"require":"prefer";
        if(!string.IsNullOrWhiteSpace(settings.RootCertificate))start.Environment["PGSSLROOTCERT"]=settings.RootCertificate;
        using var process=System.Diagnostics.Process.Start(start)??throw new InvalidOperationException("Could not start pg_dump.");
        var output=process.StandardOutput.ReadToEndAsync();var error=process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();await error;
        if(process.ExitCode!=0){Console.Error.WriteLine("Database export failed. Verify pg_dump version, SSL configuration and database permissions.");return 1;}
        if(mode=="--backup-public")Console.WriteLine("Public schema and record backup completed. Keep this private archive out of source control.");
        else Console.Write(await output);
        return 0;
    }
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
    if(mode=="--status")
    {
        var counts=new Dictionary<string,long>();
        foreach(var table in new[]{"profiles","service_accounts","account_access","bills","offline_payments","service_concerns","repair_tickets","announcements"})
        {
            await using var count=new NpgsqlCommand("SELECT count(*) FROM public."+table,inspectionConnection,readTransaction);
            counts[table]=(long)(await count.ExecuteScalarAsync())!;
        }
        var migrations=new List<string>();
        await using(var exists=new NpgsqlCommand("SELECT to_regclass('public.\"__EFMigrationsHistory\"') IS NOT NULL",inspectionConnection,readTransaction))
        {
            if(await exists.ExecuteScalarAsync() is true)
            {
                await using var query=new NpgsqlCommand("SELECT \"MigrationId\" FROM public.\"__EFMigrationsHistory\" ORDER BY \"MigrationId\"",inspectionConnection,readTransaction);
                await using var reader=await query.ExecuteReaderAsync();
                while(await reader.ReadAsync())migrations.Add(reader.GetString(0));
            }
        }
        Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new{Counts=counts,Migrations=migrations}));
        await readTransaction.RollbackAsync();return 0;
    }
    var sql=await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"inspect.sql"));
    await using var command=new NpgsqlCommand(sql,inspectionConnection,readTransaction){CommandTimeout=30};
    Console.WriteLine(await command.ExecuteScalarAsync());await readTransaction.RollbackAsync();return 0;
}
catch(InvalidOperationException exception)
{ Console.Error.WriteLine(exception.Message);return 1; }
catch(Exception exception) when(exception is NpgsqlException or ArgumentException or IOException or System.ComponentModel.Win32Exception)
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
