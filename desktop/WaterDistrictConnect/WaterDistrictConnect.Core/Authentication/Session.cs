using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using WaterDistrictConnect.Core.Domain;
using WaterDistrictConnect.Core.Persistence;

namespace WaterDistrictConnect.Core.Authentication;
public sealed class Session
{
    public Guid? UserId { get; internal set; }
    public void Clear() => UserId = null;
}
public sealed record Identity(Guid Id, string Username, string Name, string[] Permissions, Guid? AccountId, string[]? Roles = null)
{
    public bool Has(string permission) => Permissions.Contains(permission);
    public bool IsClient => Has(Domain.Permissions.Client) && !Has(Domain.Permissions.ReadOffice);
    public string RoleLabel => Roles is { Length: > 0 } ? string.Join(", ", Roles) : IsClient ? "Client" : "Office";
}
public sealed class AuthenticationService(IDbContextFactory<WaterDbContext> factory, Session session)
{
    public async Task<Identity> LoginAsync(string username, string password)
    {
        session.Clear();
        username = InputRules.Required(username, "Username", 64).ToLowerInvariant();
        InputRules.Required(password, "Password", 500);
        await using var db = await factory.CreateDbContextAsync();
        var user = await db.Users.SingleOrDefaultAsync(x => x.Username == username.Trim().ToLowerInvariant() && x.Active);
        var hasher = new PasswordHasher<User>();
        if (user == null || hasher.VerifyHashedPassword(user, user.PasswordHash, password) == PasswordVerificationResult.Failed)
            throw new BusinessException("Username or password is incorrect.");
        try
        {
            session.UserId = user.Id;
            return await Access.CurrentAsync(db, session);
        }
        catch { session.Clear(); throw; }
    }
}
public static class Access
{
    public static async Task<Identity> CurrentAsync(WaterDbContext db, Session session)
    {
        if (session.UserId == null) throw new BusinessException("Please sign in again.");
        var user = await db.Users.Include(x => x.Roles).ThenInclude(x => x.Role).ThenInclude(x => x.Permissions).Include(x => x.Ownerships).SingleOrDefaultAsync(x => x.Id == session.UserId && x.Active);
        if (user == null) throw new BusinessException("Your session is no longer available. Please sign in again.");
        return new(user.Id, user.Username, user.DisplayName, user.Roles.SelectMany(x => x.Role.Permissions.Select(p => p.Permission)).Distinct().ToArray(), user.Ownerships.Select(x => (Guid?)x.CustomerAccountId).SingleOrDefault(), user.Roles.Select(x => x.Role.Name).Order().ToArray());
    }
    public static void Require(Identity who, string permission) { if (!who.Has(permission)) throw new BusinessException("You do not have permission for this operation."); }
    public static void Account(Identity who, Guid account) { if (!who.Has(Permissions.ReadOffice) && (!who.Has(Permissions.Client) || who.AccountId != account)) throw new BusinessException("Record unavailable for this account."); }
}
