namespace WaterDistrictConnect.Core.Domain;

public static class ConcernLabels
{
    public static readonly ConcernCategory[] Categories = [ConcernCategory.WaterLeak, ConcernCategory.LowNoWaterSupply, ConcernCategory.OtherTechnicalConcern, ConcernCategory.BillingPaymentInquiry, ConcernCategory.GeneralInquiry];
    public static string Category(ConcernCategory c) => c switch { ConcernCategory.WaterLeak => "Water Leak", ConcernCategory.LowNoWaterSupply => "Low/No Water Supply", ConcernCategory.OtherTechnicalConcern => "Other Technical Concern", ConcernCategory.BillingPaymentInquiry => "Billing/Payment Inquiry", _ => "General Inquiry" };
    public static string State(ConcernState s) => s switch { ConcernState.Submitted => "Submitted", ConcernState.UnderReview => "Under Review", ConcernState.AwaitingRepair => "Awaiting Repair", ConcernState.Resolved => "Resolved", _ => "Closed" };
    public static string Channel(IntakeChannel c) => c switch { IntakeChannel.DesktopClient => "Desktop Client", IntakeChannel.Telephone => "Telephone", IntakeChannel.WalkIn => "Walk-in", _ => "Other" };
    public static bool Technical(ConcernCategory c) => c is ConcernCategory.WaterLeak or ConcernCategory.LowNoWaterSupply or ConcernCategory.OtherTechnicalConcern;
}
public static class ConcernPolicy
{
    public static bool Permitted(ServiceConcern concern, ConcernAction action)
    {
        // Use the same transition policy for available UI actions and service enforcement.
        try { Next(concern, action, action == ConcernAction.Reclassify
            ? (concern.Category == ConcernCategory.GeneralInquiry ? ConcernCategory.WaterLeak : ConcernCategory.GeneralInquiry)
            : concern.Category, "Check permitted action"); return true; }
        catch (BusinessException) { return false; }
    }
    public static string Meaningful(string value)
    {
        var text = InputRules.Required(value, "Response or reason", 4000);
        if (text.Length < 10) throw new BusinessException("Provide a meaningful response or reason of at least 10 characters.");
        return text;
    }
    public static ConcernState Next(ServiceConcern c, ConcernAction action, ConcernCategory category, string text)
    {
        Meaningful(text);
        if (!Enum.IsDefined(category) || !Enum.IsDefined(action)) throw new BusinessException("Choose a valid action and category.");
        if (action == ConcernAction.Reclassify)
        {
            if (c.State is not (ConcernState.Submitted or ConcernState.UnderReview) || c.Ticket != null) throw new BusinessException("Only open concerns without a repair ticket can be reclassified.");
            if (category == c.Category) throw new BusinessException("Choose a different classification and record why it is correct.");
            return c.State;
        }
        if (category != c.Category) throw new BusinessException("Use Reclassify to correct the category with a recorded reason.");
        return action switch
        {
            ConcernAction.Review when c.State == ConcernState.Submitted => ConcernState.UnderReview,
            ConcernAction.Respond when c.State is ConcernState.Submitted or ConcernState.UnderReview or ConcernState.AwaitingRepair => c.State == ConcernState.Submitted ? ConcernState.UnderReview : c.State,
            ConcernAction.InternalNote when c.State is not ConcernState.Closed => c.State,
            ConcernAction.Resolve when c.State == ConcernState.UnderReview && !ConcernLabels.Technical(c.Category) && c.Ticket == null => ConcernState.Resolved,
            ConcernAction.Close when c.State == ConcernState.Resolved && !ConcernLabels.Technical(c.Category) && c.Ticket == null => ConcernState.Closed,
            ConcernAction.Reopen when c.State is ConcernState.Resolved or ConcernState.Closed && c.Ticket == null => ConcernState.UnderReview,
            _ => throw new BusinessException("This action is not permitted in the current state. Technical repairs must use the future repair workflow; Awaiting Repair cannot be selected manually.")
        };
    }
}
