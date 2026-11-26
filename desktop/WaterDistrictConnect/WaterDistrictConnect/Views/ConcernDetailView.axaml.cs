using Avalonia.Controls;
using WaterDistrictConnect.Core.Domain;
using WaterDistrictConnect.ViewModels;
namespace WaterDistrictConnect.Views;
public partial class ConcernDetailView : UserControl
{
    public ConcernDetailView() => InitializeComponent();
    private void OfficeActionSelected(object? sender, SelectionChangedEventArgs e)
    {
        // Ignore transient selector clearing while allowed choices are bound or replaced.
        if (sender is ComboBox { SelectedItem: Selection<ConcernAction> choice } && DataContext is ConcernDetailViewModel vm)
            vm.Action = choice;
    }
}
