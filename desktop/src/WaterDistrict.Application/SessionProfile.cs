namespace WaterDistrict.Application;

public sealed record SessionProfile(Guid UserId, string DisplayName, string Role, string[] Permissions);
public sealed record DependencyStatus(string Status, string Message);
