using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;

namespace WaterDistrictConnect.ViewModels;

public partial class BillingViewModel : ViewModelBase
{
    private readonly WaterService service;
    public bool CanManage { get; }
    public string Title => CanManage ? "Billing" : "My Bills";
    public string Subtitle => CanManage ? "Create monthly bills, choose deadlines, and record payments." : "View your monthly charges, deadlines, and payment status.";
    [ObservableProperty] private BillRow[] rows = [];
    [ObservableProperty] private CustomerAccount[] accounts = [];
    [ObservableProperty] private CustomerAccount? account;
    [ObservableProperty] private BillRow? selectedBill;
    [ObservableProperty] private DateTimeOffset? billingMonth = DateTimeOffset.Now;
    [ObservableProperty] private DateTime? dueDate = DateTime.Today.AddDays(15);
    [ObservableProperty] private decimal? amount;
    [ObservableProperty] private bool paid;
    public bool Empty => Rows.Length == 0;
    partial void OnRowsChanged(BillRow[] value) => OnPropertyChanged(nameof(Empty));
    partial void OnSelectedBillChanged(BillRow? value)
    {
        if (value == null) return;
        Account = Accounts.FirstOrDefault(x => x.Id == value.AccountId);
        BillingMonth = new DateTimeOffset(value.Month.ToDateTime(TimeOnly.MinValue));
        DueDate = value.DueDate.ToDateTime(TimeOnly.MinValue);
        Amount = value.Amount; Paid = value.PaidAt.HasValue;
    }
    public BillingViewModel(WaterService service, Identity who)
    { this.service = service; CanManage = WaterService.CanManageBilling(who); _ = RefreshAsync(); }
    [RelayCommand] private Task RefreshAsync() => RunAsync(async () => {
        if (CanManage) Accounts = await service.AccountsAsync(AccountSearch);
        Rows = await service.BillsAsync(); SelectedBill = null;
    });
    [ObservableProperty] private string accountSearch = "";
    [RelayCommand] private Task SearchAccountsAsync() => RunAsync(async () => Accounts = await service.AccountsAsync(AccountSearch));
    [RelayCommand] private void NewBill() { SelectedBill = null; Account = null; Amount = null; Paid = false; BillingMonth = DateTimeOffset.Now; DueDate = DateTime.Today.AddDays(15); }
    [RelayCommand] private Task SaveAsync() => RunAsync(async () => {
        if (Account == null || BillingMonth == null || DueDate == null || Amount == null) throw new BusinessException("Choose an account, billing month, due date, and amount.");
        await service.SaveBillAsync(SelectedBill?.Id, SelectedBill?.Version, Account.Id, DateOnly.FromDateTime(BillingMonth.Value.DateTime), DateOnly.FromDateTime(DueDate.Value), Amount.Value, Paid);
        Rows = await service.BillsAsync(); NewBill(); Success = "Bill saved.";
    });
}
