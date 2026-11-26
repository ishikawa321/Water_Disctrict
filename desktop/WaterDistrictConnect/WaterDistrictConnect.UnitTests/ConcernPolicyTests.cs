using WaterDistrictConnect.Core.Domain;

namespace WaterDistrictConnect.UnitTests;

[Trait("Phase", "2")]
public class ConcernPolicyTests
{
    [Fact] public void EveryCategoryAndChannelHasAnExplicitLabel()
    {
        Assert.Equal(5, ConcernLabels.Categories.Length);
        Assert.Equal(3, ConcernLabels.Categories.Count(ConcernLabels.Technical));
        Assert.Equal("Walk-in", ConcernLabels.Channel(IntakeChannel.WalkIn));
        Assert.Equal("Low/No Water Supply", ConcernLabels.Category(ConcernCategory.LowNoWaterSupply));
    }
    [Fact] public void AwaitingRepairCannotBeChosenByAnyPhaseTwoAction()
    {
        foreach (var state in new[] { ConcernState.Submitted, ConcernState.UnderReview, ConcernState.Resolved, ConcernState.Closed })
        foreach (var category in ConcernLabels.Categories)
        foreach (var action in Enum.GetValues<ConcernAction>())
        {
            var c = new ServiceConcern { State = state, Category = category };
            if (ConcernPolicy.Permitted(c, action))
                Assert.NotEqual(ConcernState.AwaitingRepair, ConcernPolicy.Next(c, action,
                    action == ConcernAction.Reclassify ? (category == ConcernCategory.GeneralInquiry ? ConcernCategory.WaterLeak : ConcernCategory.GeneralInquiry) : category, "Meaningful action explanation"));
        }
    }
    [Theory] [InlineData(ConcernState.Resolved)] [InlineData(ConcernState.Closed)]
    public void ReopenRequiresReasonAndRejectsTicketLinkedConcerns(ConcernState state)
    {
        var c = new ServiceConcern { State = state, Category = ConcernCategory.GeneralInquiry };
        Assert.Throws<BusinessException>(() => ConcernPolicy.Next(c, ConcernAction.Reopen, c.Category, ""));
        Assert.Equal(ConcernState.UnderReview, ConcernPolicy.Next(c, ConcernAction.Reopen, c.Category, "Reconsider this fictional inquiry"));
        c.Ticket = new(); Assert.False(ConcernPolicy.Permitted(c, ConcernAction.Reopen));
    }
    [Fact] public void ClassificationMustBeAnExplicitReasonedCorrection()
    {
        var c = new ServiceConcern { State = ConcernState.UnderReview, Category = ConcernCategory.WaterLeak };
        Assert.Throws<BusinessException>(() => ConcernPolicy.Next(c, ConcernAction.Respond, ConcernCategory.GeneralInquiry, "Attempt implicit reclassification"));
        Assert.Throws<BusinessException>(() => ConcernPolicy.Next(c, ConcernAction.Reclassify, ConcernCategory.GeneralInquiry, "short"));
        Assert.Equal(c.State, ConcernPolicy.Next(c, ConcernAction.Reclassify, ConcernCategory.GeneralInquiry, "Original category was entered incorrectly"));
    }
    [Theory] [InlineData(ConcernCategory.WaterLeak)] [InlineData(ConcernCategory.LowNoWaterSupply)] [InlineData(ConcernCategory.OtherTechnicalConcern)]
    public void TechnicalConcernsRequireFutureRepairWorkflow(ConcernCategory category)
    {
        var c = new ServiceConcern { State = ConcernState.UnderReview, Category = category };
        Assert.False(ConcernPolicy.Permitted(c, ConcernAction.Resolve));
        Assert.True(ConcernPolicy.Permitted(c, ConcernAction.Respond));
        c.State = ConcernState.Resolved; Assert.False(ConcernPolicy.Permitted(c, ConcernAction.Close));
    }
}
