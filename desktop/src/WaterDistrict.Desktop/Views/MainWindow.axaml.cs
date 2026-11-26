using Avalonia.Controls;
using Avalonia.Threading;
using WaterDistrict.Desktop.ViewModels;

namespace WaterDistrict.Desktop.Views;

public partial class MainWindow : Window
{
    private readonly DispatcherTimer accountRefresh = new() { Interval = TimeSpan.FromSeconds(30) };
    public MainWindow()
    {
        InitializeComponent();
        accountRefresh.Tick += async (_, _) => await RefreshAccounts();
        Opened += (_, _) => accountRefresh.Start();
        Closed += (_, _) => accountRefresh.Stop();
        Activated += async (_, _) => await RefreshAccounts();
    }

    private async Task RefreshAccounts()
    {
        if (IsActive && DataContext is MainViewModel { IsAccounts: true, IsBusy: false,
                Office: { IsBusy: false } office })
            await office.RefreshCommand.ExecuteAsync(null);
    }
}
