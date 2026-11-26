using WaterDistrict.Application;
namespace WaterDistrict.Api;

public static class WorkflowEndpoints
{
    private static SessionProfile Actor(HttpContext http) => (SessionProfile)http.Items[DesktopAuthorizationHandler.SessionItem]!;
    public static void MapWorkflows(this WebApplication app)
    {
        var group = app.MapGroup("/api/workflow").RequireAuthorization("Desktop");
        group.MapGet("/accounts", (HttpContext http, IWorkflowService service, string? search, CancellationToken token) => service.AccountsAsync(Actor(http),search,token));
        group.MapGet("/assignees", (HttpContext http, IWorkflowService service, CancellationToken token) => service.AssigneesAsync(Actor(http),token)).RequireAuthorization("Admin");
        group.MapGet("/concerns", (HttpContext http, IWorkflowService service, string? search, string? status, CancellationToken token) => service.ConcernsAsync(Actor(http),search,status,token));
        group.MapGet("/concerns/{id:guid}", (HttpContext http, IWorkflowService service, Guid id, CancellationToken token) => service.ConcernAsync(Actor(http),id,token));
        group.MapPost("/concerns", (HttpContext http, IWorkflowService service, CreateConcern input, CancellationToken token) => service.CreateConcernAsync(Actor(http),input,token));
        group.MapPut("/concerns/{id:guid}/review", (HttpContext http, IWorkflowService service, Guid id, ReviewConcern input, CancellationToken token) => service.ReviewConcernAsync(Actor(http),id,input,token));
        group.MapGet("/tickets", (HttpContext http, IWorkflowService service, string? search, string? status, CancellationToken token) => service.TicketsAsync(Actor(http),search,status,token));
        group.MapGet("/tickets/{id:guid}", (HttpContext http, IWorkflowService service, Guid id, CancellationToken token) => service.TicketAsync(Actor(http),id,token));
        group.MapPost("/tickets", (HttpContext http, IWorkflowService service, CreateTicket input, CancellationToken token) => service.CreateTicketAsync(Actor(http),input,token)).RequireAuthorization("Admin");
        group.MapPut("/tickets/{id:guid}", (HttpContext http, IWorkflowService service, Guid id, UpdateTicket input, CancellationToken token) => service.UpdateTicketAsync(Actor(http),id,input,token));
    }
}
