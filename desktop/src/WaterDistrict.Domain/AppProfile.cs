namespace WaterDistrict.Domain;

public static class AppRoles
{
    public const string Admin = "admin";
    public const string Staff = "staff";
    public const string Client = "client";
    public static bool HasDesktopAccess(string role) => role is Admin or Staff;
}

public sealed class AppProfile
{
    public Guid UserId { get; set; }
    public string DisplayName { get; set; } = "";
    public string Role { get; set; } = "";
    public bool Active { get; set; }
}
