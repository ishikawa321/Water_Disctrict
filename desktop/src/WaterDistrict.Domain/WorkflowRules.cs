namespace WaterDistrict.Domain;

public sealed class WorkflowException(string code, string message, int statusCode = 422) : Exception(message)
{
    public string Code { get; } = code;
    public int StatusCode { get; } = statusCode;
}

public static class WorkflowRules
{
    public static readonly string[] Categories = ["Water supply", "Billing inquiry", "Repair request", "Other"];
    public static readonly string[] ConcernStates = ["Submitted", "Under review", "Resolved", "Closed"];
    public static readonly string[] TicketStates = ["Open", "Assigned", "In progress", "Resolved"];

    public static string Required(string? value, string label, int maximum)
    {
        var text = value?.Trim() ?? "";
        if (text.Length == 0 || text.Length > maximum)
            throw new WorkflowException("validation", $"{label} is required and must be at most {maximum} characters.");
        return text;
    }

    public static void Review(string current, string next, string? response, bool hasTicket)
    {
        if (hasTicket) throw new WorkflowException("linked_ticket", "Use the repair ticket to update this concern.", 409);
        if (current is "Closed" or "Resolved") throw new WorkflowException("closed", "This concern is already complete.", 409);
        if (next is not ("Under review" or "Closed")) throw new WorkflowException("validation", "Choose Under review or Closed.");
        if (next == "Closed") Required(response, "Closure response", 3000);
        if (response?.Length > 3000) throw new WorkflowException("validation", "Response must be at most 3000 characters.");
    }

    public static string? ConcernLocation(double? latitude, double? longitude, string? note)
    {
        if (latitude.HasValue != longitude.HasValue ||
            latitude is double lat && (!double.IsFinite(lat) || lat < -90 || lat > 90) ||
            longitude is double lon && (!double.IsFinite(lon) || lon < -180 || lon > 180))
            throw new WorkflowException("location", "Choose a valid latitude and longitude together.");
        var trimmed = note?.Trim();
        if (trimmed?.Length > 300) throw new WorkflowException("location", "The location landmark must be at most 300 characters.");
        if (latitude is null && !string.IsNullOrEmpty(trimmed)) throw new WorkflowException("location", "Choose a location pin before adding a landmark.");
        return string.IsNullOrEmpty(trimmed) ? null : trimmed;
    }

    public static void TicketTransition(string current, string next, Guid? assignee, string note)
    {
        Required(note, "Update note", 3000);
        var permitted = current switch
        {
            "Open" => next is "Open" or "Assigned",
            "Assigned" => next is "Assigned" or "In progress" or "Resolved",
            "In progress" => next is "In progress" or "Resolved",
            "Completed" => next is "In progress" or "Resolved",
            _ => false
        };
        if (!permitted) throw new WorkflowException("transition", $"Cannot change {current} to {next}.", 409);
        if (next != "Open" && assignee is null)
            throw new WorkflowException("assignee", "Select an active staff member before advancing the ticket.");
        if (next == "Open" && assignee is not null)
            throw new WorkflowException("assignee", "Use Assigned status when assigning a staff member.");
    }
}
