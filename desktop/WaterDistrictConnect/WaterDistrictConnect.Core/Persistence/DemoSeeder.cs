using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using WaterDistrictConnect.Core.Domain;
namespace WaterDistrictConnect.Core.Persistence;
public static class DemoSeeder
{
    public const string Password = "WaterDemo!2026";
    public static async Task SeedAsync(WaterDbContext db, bool sampleData = false)
    {
        await using var tx = await db.Database.BeginTransactionAsync();
        // Serializes simultaneous demo initializations without resetting existing records.
        await db.Database.ExecuteSqlRawAsync("SELECT pg_advisory_xact_lock(81912026)");
        var definitions = new Dictionary<string, string[]> {
            ["Administrator"] = [Permissions.ReadOffice, Permissions.Intake, Permissions.Respond, Permissions.Repair],
            ["Concern handler"] = [Permissions.ReadOffice, Permissions.Intake, Permissions.Respond],
            ["Ticket coordinator"] = [Permissions.ReadOffice, Permissions.Repair], ["Office viewer"] = [Permissions.ReadOffice], ["Client"] = [Permissions.Client] };
        foreach (var (name, permissions) in definitions)
        {
            if (!await db.Roles.AnyAsync(x => x.Name == name)) db.Roles.Add(new() { Name = name, Permissions = permissions.Select(x => new RolePermission { Permission = x }).ToList() });
        }
        await db.SaveChangesAsync();
        var accounts = new[] { ("000101", "Amara Demo", "12 Sample River Street, Maramag"), ("000102", "Benito Demo", "24 Sample Spring Lane, Maramag"), ("000103", "Clara Demo", "36 Sample Water Avenue, Maramag") };
        foreach (var (number, name, address) in accounts) if (!await db.Accounts.AnyAsync(x => x.Number == number)) db.Accounts.Add(new() { Number = number, Name = name, Address = address });
        foreach (var name in new[] { "Dario Resource (fictional)", "Elena Resource (fictional)", "Felix Resource (fictional)" }) if (!await db.Plumbers.AnyAsync(x => x.Name == name)) db.Plumbers.Add(new() { Name = name, Available = !name.StartsWith("Felix"), AvailabilityNote = name.StartsWith("Felix") ? "Unavailable in this demo scenario." : "Available in this demo scenario; office confirmation required." });
        await db.SaveChangesAsync();
        var users = new[] { ("admin", "Demo Administrator", "Administrator", ""), ("handler", "Demo Concern Handler", "Concern handler", ""), ("coordinator", "Demo Ticket Coordinator", "Ticket coordinator", ""), ("viewer", "Demo Office Viewer", "Office viewer", ""), ("amara", "Amara Demo", "Client", "000101"), ("benito", "Benito Demo", "Client", "000102"), ("clara", "Clara Demo", "Client", "000103") };
        foreach (var (username, name, role, account) in users)
        {
            if (await db.Users.AnyAsync(x => x.Username == username)) continue;
            var user = new User { Username = username, DisplayName = name }; user.PasswordHash = new PasswordHasher<User>().HashPassword(user, Password);
            user.Roles.Add(new() { RoleId = (await db.Roles.SingleAsync(x => x.Name == role)).Id });
            if (account != "") user.Ownerships.Add(new() { CustomerAccountId = (await db.Accounts.SingleAsync(x => x.Number == account)).Id });
            db.Users.Add(user);
        }
        await db.SaveChangesAsync();
        if (sampleData && !await db.Concerns.AnyAsync(x => x.Reference == "C-DEMO-SAMPLE"))
        {
            var actor = await db.Users.SingleAsync(x => x.Username == "amara");
            var c = new ServiceConcern { Reference = "C-DEMO-SAMPLE", CustomerAccountId = (await db.Accounts.SingleAsync(x => x.Number == "000101")).Id, RecordedById = actor.Id, Category = ConcernCategory.OtherTechnicalConcern, Subject = "Sample low water pressure", Description = "Fictional concern for exploring the office review workflow.", Location = accounts[0].Item3 };
            c.Events.Add(new() { ActorId = actor.Id, Kind = "Receipt", Text = "Demo sample received — awaiting office review; not a human response." }); db.Concerns.Add(c); await db.SaveChangesAsync();
        }
        await tx.CommitAsync();
    }
}
