using WaterDistrictConnect.Core.Domain;
namespace WaterDistrictConnect.UnitTests;
public class TicketPolicyTests
{
    [Fact] public void StartWithoutAssignmentIsRejectedWithoutMutation()
    {
        var t = new RepairTicket(); var v = t.Version;
        Assert.Throws<BusinessException>(() => TicketPolicy.Apply(t, TicketAction.Start, "Begin work", null, DateTimeOffset.UtcNow));
        Assert.Equal(TicketState.Unassigned, t.State); Assert.Equal(v, t.Version); Assert.Null(t.FirstAssignedAt);
    }
    [Fact] public void ReassignmentPreservesFirstAssignmentAndRequiresReason()
    {
        var t = new RepairTicket(); var first = DateTimeOffset.UtcNow.AddHours(-1); var a = new PlumberResource(); var b = new PlumberResource();
        TicketPolicy.Apply(t, TicketAction.Assign, "Initial assignment", a, first);
        Assert.Throws<BusinessException>(() => TicketPolicy.Apply(t, TicketAction.Assign, " ", b, DateTimeOffset.UtcNow));
        Assert.Equal(a.Id, t.PlumberResourceId);
        TicketPolicy.Apply(t, TicketAction.Assign, "Resource unavailable; handover", b, DateTimeOffset.UtcNow);
        Assert.Equal(first, t.FirstAssignedAt); Assert.Equal(b.Id, t.PlumberResourceId);
    }
    [Fact] public void ResolutionAndClosureRequireCompletionEvidence()
    {
        var t = new RepairTicket { State = TicketState.InProgress, PlumberResourceId = Guid.NewGuid() };
        Assert.Throws<BusinessException>(() => TicketPolicy.Apply(t, TicketAction.Resolve, "", null, DateTimeOffset.UtcNow));
        TicketPolicy.Apply(t, TicketAction.Resolve, "Demo leak repaired and checked", null, DateTimeOffset.UtcNow);
        Assert.Equal(TicketState.Resolved, t.State); Assert.NotNull(t.ResolvedAt);
        Assert.Throws<BusinessException>(() => TicketPolicy.Apply(t, TicketAction.Close, "", null, DateTimeOffset.UtcNow));
        TicketPolicy.Apply(t, TicketAction.Close, "SIGNED-DEMO-JO-01", null, DateTimeOffset.UtcNow);
        Assert.Equal(TicketState.Closed, t.State); Assert.Equal("SIGNED-DEMO-JO-01", t.SignedJobOrder); Assert.NotNull(t.ClosedAt);
    }
    [Fact] public void ReopenReturnsToAssignedAndClearsCurrentCompletion()
    {
        var t = new RepairTicket { State = TicketState.Closed, PlumberResourceId = Guid.NewGuid(), CompletionSummary = "Old completion", SignedJobOrder = "Old JO", FirstAssignedAt = DateTimeOffset.UtcNow.AddDays(-1), ClosedAt = DateTimeOffset.UtcNow };
        var first = t.FirstAssignedAt;
        Assert.Throws<BusinessException>(() => TicketPolicy.Apply(t, TicketAction.Reopen, "", null, DateTimeOffset.UtcNow));
        TicketPolicy.Apply(t, TicketAction.Reopen, "Issue recurred", null, DateTimeOffset.UtcNow);
        Assert.Equal(TicketState.Assigned, t.State); Assert.Equal(first, t.FirstAssignedAt); Assert.Null(t.ClosedAt); Assert.Empty(t.CompletionSummary); Assert.Empty(t.SignedJobOrder);
    }
    [Fact] public void UnavailableResourceCannotBeAssigned()
    {
        var t = new RepairTicket(); Assert.Throws<BusinessException>(() => TicketPolicy.Apply(t, TicketAction.Assign, "Assignment", new PlumberResource { Available = false }, DateTimeOffset.UtcNow)); Assert.Null(t.PlumberResourceId);
    }
    [Theory] [InlineData(TicketState.Unassigned)] [InlineData(TicketState.Assigned)] [InlineData(TicketState.InProgress)] [InlineData(TicketState.Closed)]
    public void OnlyResolvedTicketsCanClose(TicketState state)
    {
        var t = new RepairTicket { State = state }; Assert.Throws<BusinessException>(() => TicketPolicy.Apply(t, TicketAction.Close, "SIGNED-JO", null, DateTimeOffset.UtcNow)); Assert.Equal(state, t.State);
    }
}
