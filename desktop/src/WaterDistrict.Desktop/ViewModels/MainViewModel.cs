using CommunityToolkit.Mvvm.ComponentModel;

namespace WaterDistrict.Desktop.ViewModels;

public partial class MainViewModel : ViewModelBase
{
    [ObservableProperty]
    public partial string Greeting { get; set; } = "Water District administration ? foundation ready";
}
