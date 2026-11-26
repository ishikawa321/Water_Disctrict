using System.Collections.ObjectModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WaterDistrict.Application;
using WaterDistrict.Domain;
namespace WaterDistrict.Desktop.ViewModels;

public partial class OfficeViewModel:ViewModelBase
{
    private readonly IOfficeClient client;
    public OfficeViewModel(IOfficeClient client)
    {
        this.client=client;
        Payments.CollectionChanged+=(_,_)=>OnPropertyChanged(nameof(VisiblePayments));
    }
    [ObservableProperty,NotifyPropertyChangedFor(nameof(VisiblePayments))] private bool filterPayments;
    public IEnumerable<OfficePayment> VisiblePayments=>FilterPayments && SelectedBill is not null?Payments.Where(row=>row.BillNumber==SelectedBill.BillNumber):Payments;
    public event Action<SessionClientException>? SessionLost;
    public ObservableCollection<OfficeRegistration> PendingRegistrations { get; }=[];
    [ObservableProperty] private OfficeRegistration? selectedRegistration;
    public ObservableCollection<OfficeAccount> Accounts { get; }=[];
    public ObservableCollection<OfficeAccount> ActiveAccounts { get; }=[];
    public ObservableCollection<OfficeBill> Bills { get; }=[];
    public ObservableCollection<OfficePayment> Payments { get; }=[];
    public ObservableCollection<OfficeAnnouncement> Announcements { get; }=[];
    [ObservableProperty,NotifyPropertyChangedFor(nameof(IsAccounts)),NotifyPropertyChangedFor(nameof(IsBills)),NotifyPropertyChangedFor(nameof(IsPayments)),NotifyPropertyChangedFor(nameof(IsAnnouncements)),NotifyPropertyChangedFor(nameof(PageTitle)),NotifyPropertyChangedFor(nameof(PageDescription))]
    private string page="Accounts";
    public string PageTitle => Page switch
    {
        "Accounts" => "Service accounts", "Bills" => "Billing records",
        "Payments" => "Verified payments", _ => "Announcements"
    };
    public string PageDescription => Page switch
    {
        "Accounts" => "Review pending registrations and approve service accounts.",
        "Bills" => "Manage district billing records and outstanding balances.",
        "Payments" => "A clear record of verified offline payments.",
        _ => "Keep consumers informed with district news and service notices."
    };
    [ObservableProperty,NotifyCanExecuteChangedFor(nameof(ApproveRegistrationCommand)),NotifyCanExecuteChangedFor(nameof(RefreshCommand)),NotifyCanExecuteChangedFor(nameof(SaveBillCommand)),NotifyCanExecuteChangedFor(nameof(SavePaymentCommand)),NotifyCanExecuteChangedFor(nameof(SaveAnnouncementCommand)),NotifyCanExecuteChangedFor(nameof(LoadSummaryCommand))]
    private bool isBusy;
    [ObservableProperty,NotifyPropertyChangedFor(nameof(HasMessage))] private string message="";
    [ObservableProperty] private string pendingText="-";
    [ObservableProperty] private string activeRepairsText="-";
    [ObservableProperty] private OfficeAccount? selectedAccount;
    [ObservableProperty] private string billNumber="";
    [ObservableProperty] private DateTimeOffset? periodStart=DateTimeOffset.Now.Date;
    [ObservableProperty] private DateTimeOffset? periodEnd=DateTimeOffset.Now.Date;
    [ObservableProperty] private DateTimeOffset? dueDate=DateTimeOffset.Now.Date;
    [ObservableProperty] private string billAmount="";
    [ObservableProperty,NotifyPropertyChangedFor(nameof(VisiblePayments))] private OfficeBill? selectedBill;
    [ObservableProperty] private string receiptReference="";
    [ObservableProperty] private DateTimeOffset? paymentDate=DateTimeOffset.Now.Date;
    [ObservableProperty] private string paymentAmount="";
    [ObservableProperty] private bool verified;
    [ObservableProperty] private OfficeAnnouncement? selectedAnnouncement;
    [ObservableProperty] private string noticeTitle="";
    [ObservableProperty] private string noticeMessage="";
    [ObservableProperty] private bool published;
    [ObservableProperty,NotifyPropertyChangedFor(nameof(NoticeTitleLimit))] private bool interruption;
    public int NoticeTitleLimit=>150-(Interruption?OfficeAnnouncement.InterruptionPrefix.Length:0);
    public bool HasMessage=>!string.IsNullOrWhiteSpace(Message);
    public bool IsAccounts=>Page=="Accounts";
    public bool IsBills=>Page=="Bills";
    public bool IsPayments=>Page=="Payments";
    public bool IsAnnouncements=>Page=="Announcements";
    private bool Available()=>!IsBusy;
    partial void OnSelectedAnnouncementChanged(OfficeAnnouncement? value)
    { NoticeTitle=value?.DisplayTitle??"";NoticeMessage=value?.Message??"";Published=value?.Published??false;Interruption=value?.IsInterruption??false; }
    [RelayCommand(CanExecute=nameof(Available))]
    private Task LoadSummaryAsync()=>Run(async()=>
    {var summary=await client.SummaryAsync();PendingText=summary.PendingConcerns.ToString(CultureInfo.InvariantCulture);ActiveRepairsText=summary.ActiveRepairs.ToString(CultureInfo.InvariantCulture);});
    public async Task OpenAsync(string page)
    {if(IsBusy)return;Page=page;await RefreshCommand.ExecuteAsync(null);}
    [RelayCommand(CanExecute=nameof(Available))]
    private Task RefreshAsync()=>Run(async()=>
    {
        switch(Page)
        {
            case "Accounts": await LoadAccounts();Set(PendingRegistrations,await client.RegistrationsAsync());SelectedRegistration=null;break;
            case "Bills": await LoadAccounts();Set(Bills,await client.BillsAsync());break;
            case "Payments": Set(Bills,await client.BillsAsync());Set(Payments,await client.PaymentsAsync());break;
            case "Announcements":
                var selectedId=SelectedAnnouncement?.Id;var title=NoticeTitle;var body=NoticeMessage;var publish=Published;var marked=Interruption;
                Set(Announcements,await client.AnnouncementsAsync());
                if(selectedId is not null){SelectedAnnouncement=Announcements.FirstOrDefault(row=>row.Id==selectedId);NoticeTitle=title;NoticeMessage=body;Published=publish;Interruption=marked;}
                break;
        }
        Message="Records refreshed. Lists show up to 1000 records.";
    });
    [RelayCommand(CanExecute=nameof(Available))]
    private Task ApproveRegistrationAsync()=>Run(async()=>
    {
        if(SelectedRegistration is null)throw new WorkflowException("registration","Select a pending registration.");
        var saved=await client.ApproveRegistrationAsync(SelectedRegistration.UserId);
        SelectedRegistration=null;
        await LoadAccounts();Set(PendingRegistrations,await client.RegistrationsAsync());
        Message=$"Registration approved. Account {saved.AccountNumber}. The client can sign in after email confirmation.";
    });
    private async Task LoadAccounts()
    {var rows=await client.OfficeAccountsAsync();Set(Accounts,rows);Set(ActiveAccounts,rows.Where(row=>row.Active));}
    [RelayCommand(CanExecute=nameof(Available))]
    private Task SaveBillAsync()=>Run(async()=>
    {
        if(SelectedAccount is null)throw new WorkflowException("account","Select an active service account.");
        var saved=await client.AddBillAsync(new(SelectedAccount.Id,BillNumber,Date(PeriodStart),Date(PeriodEnd),Date(DueDate),Amount(BillAmount)));
        Bills.Insert(0,saved);BillNumber="";BillAmount="";Message="District-computed bill saved.";
    });
    [RelayCommand(CanExecute=nameof(Available))]
    private Task SavePaymentAsync()=>Run(async()=>
    {
        if(SelectedBill is null)throw new WorkflowException("bill","Select the bill for this payment.");
        var saved=await client.AddPaymentAsync(new(SelectedBill.Id,ReceiptReference,Date(PaymentDate),Amount(PaymentAmount),Verified));
        Payments.Insert(0,saved);ReceiptReference="";PaymentAmount="";Verified=false;Message="Verified offline payment recorded. Refresh bills to retrieve updated totals.";
    });
    [RelayCommand(CanExecute=nameof(Available))]
    private Task SaveAnnouncementAsync()=>Run(async()=>
    {
        var saved=await client.SaveAnnouncementAsync(SelectedAnnouncement?.Id,new(NoticeTitle,NoticeMessage,Published,Interruption));
        var existing=Announcements.FirstOrDefault(row=>row.Id==saved.Id);if(existing is not null)Announcements[Announcements.IndexOf(existing)]=saved;else Announcements.Insert(0,saved);
        SelectedAnnouncement=saved;Message=saved.Published?"Announcement published.":"Announcement saved as a draft.";
    });
    [RelayCommand(CanExecute=nameof(Available))]
    private void NewAnnouncement(){SelectedAnnouncement=null;NoticeTitle="";NoticeMessage="";Published=false;Interruption=false;Message="New announcement draft.";}
    private static DateOnly Date(DateTimeOffset? value)=>value is null?throw new WorkflowException("date","Select all required dates."):DateOnly.FromDateTime(value.Value.DateTime);
    private static decimal Amount(string text)=>decimal.TryParse(text.Trim(),NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture,out var amount)&&amount>0&&decimal.Round(amount,2)==amount?amount:throw new WorkflowException("amount","Enter a positive amount with at most two decimal places.");
    private async Task Run(Func<Task> operation)
    {
        if(IsBusy)return;IsBusy=true;Message="";
        try{await operation();}
        catch(SessionClientException error){Message=error.Message;if(error.RequiresSignIn)SessionLost?.Invoke(error);}
        catch(WorkflowException error){Message=error.Message;}
        finally{IsBusy=false;}
    }
    private static void Set<T>(ObservableCollection<T> target,IEnumerable<T> rows){target.Clear();foreach(var row in rows)target.Add(row);}
    public void Clear()
    {
        PendingRegistrations.Clear();SelectedRegistration=null;Accounts.Clear();ActiveAccounts.Clear();Bills.Clear();Payments.Clear();Announcements.Clear();
        SelectedAccount=null;SelectedBill=null;SelectedAnnouncement=null;FilterPayments=false;BillNumber="";BillAmount="";ReceiptReference="";PaymentAmount="";Verified=false;
        NoticeTitle="";NoticeMessage="";Published=false;Interruption=false;PendingText="-";ActiveRepairsText="-";Message="";
    }
}
