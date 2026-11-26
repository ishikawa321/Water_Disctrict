using Avalonia.Controls;

namespace WaterDistrictConnect;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Opened += (_, _) =>
        {
            // Keep the entire shell on smaller laptop displays, including the logout action.
            var screen = Screens.ScreenFromWindow(this);
            if (screen != null && (Width + 16 > screen.WorkingArea.Width / screen.Scaling ||
                                   Height + 48 > screen.WorkingArea.Height / screen.Scaling))
                WindowState = WindowState.Maximized;
        };
    }
}
