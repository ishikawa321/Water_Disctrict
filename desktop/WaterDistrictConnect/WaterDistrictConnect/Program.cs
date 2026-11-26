using Avalonia;
using System;
using Microsoft.Extensions.DependencyInjection;
using WaterDistrictConnect.Core.Persistence;

namespace WaterDistrictConnect;

class Program
{
    // Initialization code. Don't use any Avalonia, third-party APIs or any
    // SynchronizationContext-reliant code before AppMain is called: things aren't initialized
    // yet and stuff might break.
    [STAThread]
    public static void Main(string[] args)
    {
        if (Array.Exists(args, a => a == "--migrate"))
        {
            try { using var services = Composition.Create(); services.GetRequiredService<DatabaseSetup>().MigrateAsync().GetAwaiter().GetResult(); }
            catch (Exception) { Environment.ExitCode = 1; System.IO.File.WriteAllText("migration-error.txt", "Migration failed. Check MWD_CONNECTION, PostgreSQL access and permissions, then retry. No credentials are logged."); }
            return;
        }
        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    // Avalonia configuration, don't remove; also used by visual designer.
    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .LogToTrace();
}
