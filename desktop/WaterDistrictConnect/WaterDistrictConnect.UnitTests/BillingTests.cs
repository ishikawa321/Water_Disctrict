using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Authentication;

namespace WaterDistrictConnect.UnitTests;

public class BillingTests
{
    [Theory]
    [InlineData(14, "Unpaid")]
    [InlineData(15, "Due today")]
    [InlineData(16, "Overdue")]
    public void UnpaidStatusFollowsCalendarDeadline(int day, string expected)
    {
        var bill = new BillRow(Guid.NewGuid(), Guid.NewGuid(), "Account", new(2026, 11, 1), new(2026, 11, 15), 250m, null, Guid.NewGuid());
        Assert.Equal(expected, bill.StatusOn(new(2026, 11, day)));
        Assert.Equal("Paid", (bill with { PaidAt = DateTimeOffset.UtcNow }).StatusOn(new(2026, 11, day)));
    }

    [Fact]
    public void OnlyAdministratorRoleCanManageBilling()
    {
        var who = new Identity(Guid.NewGuid(), "user", "User", ["office.read", "client.own"], Guid.NewGuid(), ["Client"]);
        Assert.False(WaterService.CanManageBilling(who));
        Assert.True(WaterService.CanManageBilling(who with { Roles = ["Administrator"] }));
    }
}
