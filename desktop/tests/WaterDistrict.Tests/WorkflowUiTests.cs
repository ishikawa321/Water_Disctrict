using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using WaterDistrict.Application;
using WaterDistrict.Desktop.ViewModels;
using WaterDistrict.Desktop.Views;

namespace WaterDistrict.Tests;

public sealed class WorkflowUiTests
{
    [AvaloniaFact]
    public async Task Failed_intake_keeps_draft_and_retry_identifier_until_confirmed_success()
    {
        var client=new FakeWorkflowClient { FailWrite=true };
        var model=new WorkflowViewModel(client) { SelectedAccount=client.Account,Subject="No water",Description="No supply since this morning.",Category="Water supply" };
        await model.SaveConcernCommand.ExecuteAsync(null);
        Assert.Equal("No water",model.Subject);Assert.Equal("No supply since this morning.",model.Description);Assert.Same(client.Account,model.SelectedAccount);
        Assert.Contains("failed",model.Message);
        client.FailWrite=false;await model.SaveConcernCommand.ExecuteAsync(null);
        Assert.Equal(client.RequestIds[0],client.RequestIds[1]);Assert.Empty(model.Subject);Assert.Empty(model.Description);
        Assert.NotNull(model.SelectedConcern);Assert.Single(model.Concerns);
    }

    [AvaloniaFact]
    public async Task Review_and_dispatch_bind_saved_records_into_ticket_timeline()
    {
        var client=new FakeWorkflowClient();var model=new MainViewModel(new OfficeSession(),client);
        model.Email="admin@example.com";model.Password="test-password";await model.SignInCommand.ExecuteAsync(null);
        await model.OpenConcernsCommand.ExecuteAsync(null);
        var workflows=model.Workflows!;workflows.SelectedConcern=workflows.Concerns[0];workflows.ReviewResponse="Reviewed for repair.";
        await workflows.SaveReviewCommand.ExecuteAsync(null);
        Assert.True(workflows.CanDispatch);Assert.Equal("Under review",workflows.SelectedConcern!.Status);
        var window=new MainWindow { DataContext=model };window.Show();Capture(window,"concern-review");
        workflows.CreationNote="Dispatch repair for the reviewed report.";await workflows.CreateRepairTicketCommand.ExecuteAsync(null);
        Assert.True(model.IsTickets);Assert.Single(workflows.History);Assert.NotNull(workflows.SelectedConcern.TicketId);
        Capture(window,"ticket-open");window.Close();
    }

    [AvaloniaFact]
    public async Task Failed_ticket_save_keeps_note_and_saved_history_while_success_clears_the_note()
    {
        var client=new FakeWorkflowClient();var model=new WorkflowViewModel(client) { IsAdmin=true };
        await model.LoadTicketsCommand.ExecuteAsync(null);model.SelectedTicket=model.Tickets[0];
        await model.LoadSelectedTicketCommand.ExecuteAsync(null);
        model.TicketStatus="Assigned";model.SelectedAssignee=client.Assignee;model.TicketNote="Assign to the available repair staff.";
        client.FailWrite=true;await model.SaveTicketCommand.ExecuteAsync(null);
        Assert.Equal("Assign to the available repair staff.",model.TicketNote);Assert.Single(model.History);Assert.Equal("Open",model.SelectedTicket!.Status);
        client.FailWrite=false;await model.SaveTicketCommand.ExecuteAsync(null);
        Assert.Empty(model.TicketNote);Assert.Equal(2,model.History.Count);Assert.Equal("Assigned",model.SelectedTicket!.Status);
    }

    private static void Capture(Window window,string name)
    {
        Dispatcher.UIThread.RunJobs();AvaloniaHeadlessPlatform.ForceRenderTimerTick();using var frame=window.CaptureRenderedFrame();Assert.NotNull(frame);
        var path=Path.Combine(AppContext.BaseDirectory,"artifacts","ui");Directory.CreateDirectory(path);frame!.Save(Path.Combine(path,name+".png"),PngBitmapEncoderOptions.Default);
    }
    private sealed class OfficeSession : IDesktopSessionClient
    {
        public bool IsAuthenticated=>true;
        public Task<SessionProfile> SignInAsync(string email,string password,CancellationToken cancellationToken=default)=>Task.FromResult(new SessionProfile(Guid.NewGuid(),"Admin preview","admin",[]));
        public Task<SessionProfile> RefreshProfileAsync(CancellationToken cancellationToken=default)=>SignInAsync("","",cancellationToken);
        public Task<IReadOnlyList<StaffMember>> GetStaffAsync(CancellationToken cancellationToken=default)=>Task.FromResult<IReadOnlyList<StaffMember>>([]);
        public Task SignOutAsync()=>Task.CompletedTask;
    }
    private sealed class FakeWorkflowClient : IWorkflowClient
    {
        public AccountOption Account { get; }=new(Guid.NewGuid(),"TEST-1042","Test consumer","Test address");
        public StaffMember Assignee { get; }=new(Guid.NewGuid(),"Staff preview","staff");
        public bool FailWrite { get; set; }
        public List<Guid> RequestIds { get; }=[];
        private ConcernRecord concern;
        private TicketDetails ticket;
        public FakeWorkflowClient()
        {
            concern=new(Guid.NewGuid(),Account.Id,Account.AccountNumber,Account.HolderName,"Repair request","Leak at service connection","Visible leak near the service line.","Submitted",null,DateTimeOffset.UtcNow,null,null,1);
            ticket=new(new(Guid.NewGuid(),concern.Id,Account.AccountNumber,concern.Subject,"Open",null,null,"Repair dispatch received.",DateTimeOffset.UtcNow,1),
                [new(1,"Open","Repair dispatch received.","Admin preview",null,DateTimeOffset.UtcNow)]);
        }
        public Task<IReadOnlyList<AccountOption>> AccountsAsync(string? search=null,CancellationToken token=default)=>Task.FromResult<IReadOnlyList<AccountOption>>([Account]);
        public Task<IReadOnlyList<StaffMember>> AssigneesAsync(CancellationToken token=default)=>Task.FromResult<IReadOnlyList<StaffMember>>([Assignee]);
        public Task<IReadOnlyList<ConcernRecord>> ConcernsAsync(string? search=null,string? status=null,CancellationToken token=default)=>Task.FromResult<IReadOnlyList<ConcernRecord>>([concern]);
        public Task<ConcernRecord> ConcernAsync(Guid id,CancellationToken token=default)=>Task.FromResult(concern);
        public Task<ConcernRecord> CreateConcernAsync(CreateConcern input,CancellationToken token=default)
        {
            RequestIds.Add(input.RequestId);if(FailWrite)throw new SessionClientException("Save failed; draft retained.");
            concern=concern with { Id=input.RequestId,Subject=input.Subject,Description=input.Description };return Task.FromResult(concern);
        }
        public Task<ConcernRecord> ReviewConcernAsync(Guid id,ReviewConcern input,CancellationToken token=default)
        { concern=concern with { Version=2,Status=input.Status,Response=input.Response,ReviewedAt=DateTimeOffset.UtcNow };return Task.FromResult(concern); }
        public Task<IReadOnlyList<TicketRecord>> TicketsAsync(string? search=null,string? status=null,CancellationToken token=default)=>Task.FromResult<IReadOnlyList<TicketRecord>>([ticket.Ticket]);
        public Task<TicketDetails> TicketAsync(Guid id,CancellationToken token=default)=>Task.FromResult(ticket);
        public Task<TicketDetails> CreateTicketAsync(CreateTicket input,CancellationToken token=default)=>Task.FromResult(ticket);
        public Task<TicketDetails> UpdateTicketAsync(Guid id,UpdateTicket input,CancellationToken token=default)
        {
            if(FailWrite)throw new SessionClientException("Save failed; draft retained.");
            ticket=new(ticket.Ticket with { Version=2,Status=input.Status,AssignedToUserId=input.AssignedToUserId,AssignedTo=Assignee.DisplayName,LatestUpdate=input.Note },
                [..ticket.History,new(2,input.Status,input.Note,"Admin preview",Assignee.DisplayName,DateTimeOffset.UtcNow)]);
            return Task.FromResult(ticket);
        }
    }
}
