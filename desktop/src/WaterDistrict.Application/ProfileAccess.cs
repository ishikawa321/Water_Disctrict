using WaterDistrict.Domain;

namespace WaterDistrict.Application;

public interface IProfileReader
{
    Task<AppProfile?> FindAsync(Guid userId, string bearerToken, CancellationToken cancellationToken);
    Task<IReadOnlyList<AppProfile>> ListStaffAsync(string bearerToken, CancellationToken cancellationToken);
}

public sealed class DependencyUnavailableException(string message) : Exception(message);

public static class ProfileAccess
{
    public static SessionProfile? CreateSession(AppProfile? profile, Guid authenticatedUserId)
    {
        if (profile is null || profile.UserId != authenticatedUserId || !profile.Active || !AppRoles.HasDesktopAccess(profile.Role))
            return null;
        var permissions = profile.Role == AppRoles.Admin
            ? new[] { "concerns.review", "tickets.assign", "tickets.update", "staff.read" }
            : new[] { "concerns.review", "tickets.update.assigned" };
        return new(profile.UserId, profile.DisplayName, profile.Role, permissions);
    }
}
