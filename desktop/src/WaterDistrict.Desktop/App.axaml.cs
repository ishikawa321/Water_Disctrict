using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using WaterDistrict.Application;
using WaterDistrict.Desktop.ViewModels;
using WaterDistrict.Desktop.Views;

namespace WaterDistrict.Desktop;

public partial class App : Avalonia.Application
{
    private ServiceProvider? services;
    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            try
            {
                var configuration = new ConfigurationBuilder().SetBasePath(AppContext.BaseDirectory)
                    .AddJsonFile("appsettings.json", optional: false)
                    .AddJsonFile("appsettings.Local.json", optional: true)
                    .AddEnvironmentVariables(prefix: "WATERDISTRICT_").Build();
                var settings = DesktopSettings.Load(configuration);
                var registrations = new ServiceCollection();
                registrations.AddHttpClient("SupabaseAuth", client =>
                {
                    client.BaseAddress = new Uri(settings.SupabaseUrl.AbsoluteUri.TrimEnd('/') + "/auth/v1/");
                    client.DefaultRequestHeaders.Add("apikey", settings.PublishableKey);
                    client.Timeout = TimeSpan.FromSeconds(20);
                }).ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
                registrations.AddHttpClient("OfficeApi", client =>
                {
                    client.BaseAddress = settings.ApiUrl;
                    client.Timeout = TimeSpan.FromSeconds(20);
                }).ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
                registrations.AddSingleton<IDesktopSessionClient>(provider =>
                {
                    var clients = provider.GetRequiredService<IHttpClientFactory>();
                    return new DesktopSessionClient(clients.CreateClient("SupabaseAuth"), clients.CreateClient("OfficeApi"));
                });
                registrations.AddSingleton<MainViewModel>();
                services = registrations.BuildServiceProvider();
                desktop.MainWindow = new MainWindow { DataContext = services.GetRequiredService<MainViewModel>() };
                desktop.Exit += (_, _) => services.Dispose();
            }
            catch (Exception exception) when (exception is InvalidOperationException or IOException or FormatException)
            {
                desktop.MainWindow = new Window { Title = "Water District configuration", Width = 620, Height = 240,
                    Content = new TextBlock { Margin = new Thickness(32), TextWrapping = Avalonia.Media.TextWrapping.Wrap,
                        Text = "The desktop configuration could not be loaded. Check appsettings.json and any local overrides, then reopen the application." } };
            }
        }
        base.OnFrameworkInitializationCompleted();
    }
}
