using WaterDistrictConnect.Core.Domain;
namespace WaterDistrictConnect.ViewModels;
public sealed record Selection<T>(string Label, T? Value, string Icon = "") where T : struct
{
    public override string ToString() => Label;
}
public static class ConcernSelections
{
    public static Selection<ConcernCategory>[] Categories => ConcernLabels.Categories.Select(x => new Selection<ConcernCategory>(ConcernLabels.Category(x), x,
        WaterDistrictConnect.Core.Application.ConcernRow.IconFor(x))).ToArray();
    public static Selection<ConcernState>[] States => new[] { ConcernState.Submitted, ConcernState.UnderReview, ConcernState.AwaitingRepair, ConcernState.Resolved, ConcernState.Closed }.Select(x => new Selection<ConcernState>(ConcernLabels.State(x), x)).ToArray();
}
