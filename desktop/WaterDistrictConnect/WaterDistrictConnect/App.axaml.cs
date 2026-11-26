using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Microsoft.Extensions.DependencyInjection;
using WaterDistrictConnect.ViewModels;
using Avalonia.Markup.Xaml.Styling;
using WaterDistrictConnect.Presentation;

namespace WaterDistrictConnect;

public partial class App : Application
{
    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
        if (UiMotion.Enabled)
            Styles.Add(new StyleInclude(new Uri("avares://WaterDistrictConnect/"))
            { Source = new Uri("avares://WaterDistrictConnect/Styles/Motion.axaml") });
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            var services = Composition.Create();
            desktop.MainWindow = new MainWindow { DataContext = services.GetRequiredService<RootViewModel>() };
            desktop.Exit += (_, _) => services.Dispose();
        }

        base.OnFrameworkInitializationCompleted();
    }
}
