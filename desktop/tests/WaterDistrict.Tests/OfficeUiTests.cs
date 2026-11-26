using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using Avalonia.VisualTree;
using WaterDistrict.Application;
using WaterDistrict.Desktop.ViewModels;
using WaterDistrict.Desktop.Views;

namespace WaterDistrict.Tests;

public sealed class OfficeUiTests
{
    [AvaloniaTheory]
    [InlineData("Accounts")][InlineData("Bills")][InlineData("Payments")][InlineData("Announcements")]
    public async Task Admin_can_navigate_to_each_mobile_equivalent_office_module(string page)
    {
        var model=new MainViewModel(new Sessions("admin"),office:new FakeOffice());
        model.Email="admin@example.com";model.Password="test-password";await model.SignInCommand.ExecuteAsync(null);
        var window=new MainWindow{DataContext=model};window.Show();
        await model.OpenOfficeCommand.ExecuteAsync(page);Dispatcher.UIThread.RunJobs();
        Assert.True(model.IsOffice);Assert.Equal(page,model.Office!.Page);
        var selected = Assert.Single(window.GetVisualDescendants().OfType<Button>(), button => button.Classes.Contains("active"));
        Assert.Equal(page, selected.CommandParameter);
        Assert.Equal(selected.Content, model.WorkspaceTitle);
        Assert.Equal(model.WorkspaceTitle, model.Office.PageTitle);
        Assert.Equal("7",model.Office.PendingText);
        AvaloniaHeadlessPlatform.ForceRenderTimerTick();using var frame=window.CaptureRenderedFrame();Assert.NotNull(frame);
        var directory=Path.Combine(AppContext.BaseDirectory,"artifacts","ui");Directory.CreateDirectory(directory);
        frame!.Save(Path.Combine(directory,"office-"+page.ToLowerInvariant()+".png"),PngBitmapEncoderOptions.Default);
        window.Close();
    }
    [AvaloniaFact]
    public async Task Staff_never_sees_or_opens_admin_office_modules()
    {
        var model=new MainViewModel(new Sessions("staff"),office:new FakeOffice());model.Email="staff@example.com";model.Password="password";
        await model.SignInCommand.ExecuteAsync(null);var window=new MainWindow{DataContext=model};window.Show();
        foreach(var label in new[]{"Service accounts","Billing records","Verified payments","Announcements"})
            Assert.False(window.GetVisualDescendants().OfType<Button>().Single(button=>Equals(button.Content,label)).IsVisible);
        await model.OpenOfficeCommand.ExecuteAsync("Bills");Assert.False(model.IsOffice);window.Close();
    }
    [AvaloniaFact]
    public async Task Failed_payment_preserves_verification_and_amount_until_confirmed_save()
    {
        var client=new FakeOffice{Fail=true};var model=new OfficeViewModel(client){SelectedBill=client.Bill,ReceiptReference="R-001",PaymentAmount="100.50",Verified=true};
        await model.SavePaymentCommand.ExecuteAsync(null);Assert.Equal("100.50",model.PaymentAmount);Assert.True(model.Verified);Assert.Empty(model.Payments);
        client.Fail=false;await model.SavePaymentCommand.ExecuteAsync(null);Assert.Empty(model.PaymentAmount);Assert.False(model.Verified);Assert.Single(model.Payments);
    }
    [AvaloniaFact]
    public async Task Announcement_edit_loads_interruption_and_draft_without_losing_them_on_failure()
    {
        var client=new FakeOffice{Fail=true};var model=new OfficeViewModel(client){SelectedAnnouncement=client.Notice};
        Assert.Equal("Maintenance",model.NoticeTitle);Assert.True(model.Interruption);Assert.False(model.Published);
        model.NoticeMessage="Updated notice text.";await model.SaveAnnouncementCommand.ExecuteAsync(null);
        Assert.Equal("Updated notice text.",model.NoticeMessage);Assert.True(model.Interruption);
        client.Fail=false;model.Published=true;await model.SaveAnnouncementCommand.ExecuteAsync(null);
        Assert.True(model.SelectedAnnouncement!.Published);Assert.Equal("Updated notice text.",model.SelectedAnnouncement.Message);
    }
    [AvaloniaFact]
    public async Task Payment_history_filter_shows_only_the_selected_bill()
    {
        var client=new FakeOffice();var model=new OfficeViewModel(client);
        await model.OpenAsync("Payments");Assert.Equal(2,model.VisiblePayments.Count());
        model.SelectedBill=client.Bill;model.FilterPayments=true;
        Assert.Equal("B-001",Assert.Single(model.VisiblePayments).BillNumber);
        model.FilterPayments=false;Assert.Equal(2,model.VisiblePayments.Count());
    }
    private sealed class Sessions(string role):IDesktopSessionClient
    {
        public bool IsAuthenticated=>true;
        public Task<SessionProfile> SignInAsync(string email,string password,CancellationToken cancellationToken=default)=>Task.FromResult(new SessionProfile(Guid.NewGuid(),"Office preview",role,[]));
        public Task<SessionProfile> RefreshProfileAsync(CancellationToken cancellationToken=default)=>SignInAsync("","",cancellationToken);
        public Task<IReadOnlyList<StaffMember>> GetStaffAsync(CancellationToken cancellationToken=default)=>Task.FromResult<IReadOnlyList<StaffMember>>([]);
        public Task SignOutAsync()=>Task.CompletedTask;
    }
    private sealed class FakeOffice:IOfficeClient
    {
        public OfficeAccount Account {get;}=new(Guid.NewGuid(),"WD-001","Test holder","Test service address",true);
        public OfficeBill Bill {get;}=new(Guid.NewGuid(),"B-001","WD-001",new(2026,10,1),new(2026,10,31),new(2026,11,15),450,100);
        public OfficeAnnouncement Notice {get;}=new(Guid.NewGuid(),"[Service interruption] Maintenance","Recorded notice for consumers.",false,DateTimeOffset.UtcNow);
        public bool Fail {get;set;}
        private void Check(){if(Fail)throw new SessionClientException("Save not confirmed. Refresh before retrying; your draft was kept.");}
        public Task<OfficeSummary> SummaryAsync(CancellationToken token=default)=>Task.FromResult(new OfficeSummary(7,3));
        public Task<IReadOnlyList<OfficeAccount>> OfficeAccountsAsync(CancellationToken token=default)=>Task.FromResult<IReadOnlyList<OfficeAccount>>([Account]);
        public Task<OfficeAccount> AddAccountAsync(AddOfficeAccount input,CancellationToken token=default){Check();return Task.FromResult(Account);}
        public Task<IReadOnlyList<OfficeBill>> BillsAsync(CancellationToken token=default)=>Task.FromResult<IReadOnlyList<OfficeBill>>([Bill]);
        public Task<OfficeBill> AddBillAsync(AddOfficeBill input,CancellationToken token=default){Check();return Task.FromResult(Bill);}
        public Task<IReadOnlyList<OfficePayment>> PaymentsAsync(CancellationToken token=default)=>Task.FromResult<IReadOnlyList<OfficePayment>>([new("R-001","B-001","WD-001",new(2026,10,20),100,DateTimeOffset.UtcNow),new("R-002","B-002","WD-002",new(2026,10,21),200,DateTimeOffset.UtcNow)]);
        public Task<OfficePayment> AddPaymentAsync(AddOfficePayment input,CancellationToken token=default){Check();return Task.FromResult(new OfficePayment(input.ReceiptReference,Bill.BillNumber,Bill.AccountNumber,input.PaymentDate,input.AmountPaid,DateTimeOffset.UtcNow));}
        public Task<IReadOnlyList<OfficeAnnouncement>> AnnouncementsAsync(CancellationToken token=default)=>Task.FromResult<IReadOnlyList<OfficeAnnouncement>>([Notice]);
        public Task<OfficeAnnouncement> SaveAnnouncementAsync(Guid? id,SaveOfficeAnnouncement input,CancellationToken token=default)
        {Check();return Task.FromResult(Notice with{Title=(input.IsInterruption?OfficeAnnouncement.InterruptionPrefix:"")+input.Title,Message=input.Message,Published=input.Published});}
    }
}
