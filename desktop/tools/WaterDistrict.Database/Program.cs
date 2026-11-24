using System.Data;
using Npgsql;

var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__WaterDistrict");
if (string.IsNullOrWhiteSpace(connectionString))
{
    Console.Error.WriteLine("Set ConnectionStrings__WaterDistrict locally. No database was contacted.");
    return 2;
}
try
{
    await using var connection = new NpgsqlConnection(connectionString);
    await connection.OpenAsync();
    await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.RepeatableRead);
    await using (var readOnly = new NpgsqlCommand("SET TRANSACTION READ ONLY", connection, transaction))
        await readOnly.ExecuteNonQueryAsync();
    var sql = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "inspect.sql"));
    await using var command = new NpgsqlCommand(sql, connection, transaction) { CommandTimeout = 30 };
    Console.WriteLine(await command.ExecuteScalarAsync());
    await transaction.RollbackAsync();
    return 0;
}
catch (Exception exception) when (exception is NpgsqlException or ArgumentException or IOException)
{
    Console.Error.WriteLine("Inspection failed. Check the local connection and catalog permissions; no writes were requested.");
    return 1;
}
