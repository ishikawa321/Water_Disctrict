using Avalonia.Controls;
using Avalonia;
using Avalonia.Threading;
using System.ComponentModel;
using WaterDistrictConnect.ViewModels;
namespace WaterDistrictConnect.Views;
public partial class WorkspaceView : UserControl
{
    private WorkspaceViewModel? observed;
    public WorkspaceView()
    {
        InitializeComponent();
        DataContextChanged += (_, _) =>
        {
            if (observed != null) observed.PropertyChanged -= PageChanged;
            observed = DataContext as WorkspaceViewModel;
            if (observed != null) observed.PropertyChanged += PageChanged;
        };
    }
    private void PageChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(WorkspaceViewModel.Page))
            Dispatcher.UIThread.Post(() => this.FindControl<ScrollViewer>("PageScroll")!.Offset = new Vector(0, 0), DispatcherPriority.Loaded);
    }
}
