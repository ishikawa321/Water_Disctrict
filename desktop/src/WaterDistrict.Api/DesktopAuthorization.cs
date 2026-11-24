using Microsoft.AspNetCore.Authorization;
using WaterDistrict.Application;

namespace WaterDistrict.Api;

public sealed record ActiveDesktopProfileRequirement(bool AdminOnly = false) : IAuthorizationRequirement;

public sealed class DesktopAuthorizationHandler(IProfileReader profiles) : AuthorizationHandler<ActiveDesktopProfileRequirement>
{
    public const string SessionItem = "WaterDistrict.Session";
    protected override async Task HandleRequirementAsync(AuthorizationHandlerContext context, ActiveDesktopProfileRequirement requirement)
    {
        if (context.Resource is not HttpContext http || context.User.Identity?.IsAuthenticated != true ||
            !Guid.TryParse(context.User.FindFirst("sub")?.Value, out var userId)) return;

        if (!http.Items.TryGetValue(SessionItem, out var cached))
        {
            var header = http.Request.Headers.Authorization.ToString();
            if (!header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) return;
            var profile = await profiles.FindAsync(userId, header[7..].Trim(), http.RequestAborted);
            cached = ProfileAccess.CreateSession(profile, userId);
            http.Items[SessionItem] = cached;
        }
        if (cached is SessionProfile session && (!requirement.AdminOnly || session.Role == "admin"))
            context.Succeed(requirement);
    }
}
