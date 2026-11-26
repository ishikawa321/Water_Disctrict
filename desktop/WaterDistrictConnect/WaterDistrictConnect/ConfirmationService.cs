using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Layout;
using WaterDistrictConnect.ViewModels;
namespace WaterDistrictConnect;
// Presentation-only dialog composition. Decisions remain in application services.
public sealed class ConfirmationService : IConfirmationService
{
    public async Task<bool> ConfirmAsync(string title, string message)
    {
        if ((Application.Current?.ApplicationLifetime as IClassicDesktopStyleApplicationLifetime)?.MainWindow is not Window owner) return false;
        var dialog = new Window { Title = title, Width = 520, SizeToContent = SizeToContent.Height, CanResize = false, WindowStartupLocation = WindowStartupLocation.CenterOwner, ShowInTaskbar = false };
        var cancel = new Button { Content = "Cancel", IsCancel = true, MinWidth = 90 }; var confirm = new Button { Content = "Confirm " + title.ToLowerInvariant() }; confirm.Classes.Add("primary");
        cancel.Click += (_, _) => dialog.Close(false); confirm.Click += (_, _) => dialog.Close(true);
        var heading = new TextBlock { Text = title }; heading.Classes.Add("section");
        var body = new Border { Padding = new Thickness(16), Child = new TextBlock { Text = message, TextWrapping = Avalonia.Media.TextWrapping.Wrap } }; body.Classes.Add("card");
        dialog.Content = new StackPanel { Margin = new Thickness(24), Spacing = 20, Children = { heading, body, new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Right, Children = { cancel, confirm } } } };
        return await dialog.ShowDialog<bool>(owner);
    }
}
