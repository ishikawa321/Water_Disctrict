namespace WaterDistrictConnect.Core.Domain;

public sealed class BusinessException(string message) : Exception(message);
public static class InputRules
{
    public static string Required(string? value, string label, int max)
    {
        var s = value?.Trim() ?? "";
        if (s.Length == 0 || s.Length > max) throw new BusinessException($"{label} is required (maximum {max} characters).");
        return s;
    }
    public static string Optional(string? value, string label, int max)
    {
        var s = value?.Trim() ?? "";
        if (s.Length > max) throw new BusinessException($"{label} must be at most {max} characters.");
        return s;
    }
}
public static class TicketPolicy
{
    // Mutates only after all input/state checks pass. Database service supplies verified resource.
    public static void Apply(RepairTicket ticket, TicketAction action, string text, PlumberResource? plumber, DateTimeOffset now)
    {
        text = InputRules.Required(text, action == TicketAction.Close ? "Signed Job Order reference" : "Update / reason", 2000);
        var state = ticket.State;
        var next = action switch
        {
            TicketAction.Assign when state is TicketState.Unassigned or TicketState.Assigned or TicketState.InProgress => state == TicketState.InProgress ? state : TicketState.Assigned,
            TicketAction.Start when state == TicketState.Assigned && ticket.PlumberResourceId != null => TicketState.InProgress,
            TicketAction.Progress when state is TicketState.Assigned or TicketState.InProgress => state,
            TicketAction.Resolve when state == TicketState.InProgress => TicketState.Resolved,
            TicketAction.Close when state == TicketState.Resolved => TicketState.Closed,
            TicketAction.Reopen when state is TicketState.Resolved or TicketState.Closed => ticket.PlumberResourceId != null ? TicketState.Assigned : TicketState.Unassigned,
            _ => throw new BusinessException($"Cannot {action.ToString().ToLowerInvariant()} a ticket in {state} state.")
        };
        if (action == TicketAction.Assign && (plumber == null || !plumber.Available)) throw new BusinessException("Choose an available plumber resource.");
        if (action == TicketAction.Assign && plumber!.Id == ticket.PlumberResourceId) throw new BusinessException("This plumber is already assigned.");
        if (action == TicketAction.Close) text = InputRules.Required(text, "Signed Job Order reference", 160);
        if (action == TicketAction.Assign) { ticket.PlumberResourceId = plumber!.Id; ticket.FirstAssignedAt ??= now; }
        if (action == TicketAction.Resolve) { ticket.CompletionSummary = text; ticket.ResolvedAt = now; }
        if (action == TicketAction.Close) { ticket.SignedJobOrder = text; ticket.ClosedAt = now; }
        if (action == TicketAction.Reopen) { ticket.ResolvedAt = null; ticket.ClosedAt = null; ticket.CompletionSummary = ""; ticket.SignedJobOrder = ""; }
        ticket.State = next; ticket.Version = Guid.NewGuid();
    }
}
