using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using Avalonia.VisualTree;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using WaterDistrictConnect;
using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;
using WaterDistrictConnect.Core.Persistence;
using WaterDistrictConnect.ViewModels;
using WaterDistrictConnect.Views;

// Development-only render verification. Uses production views/commands and a disposable PostgreSQL database.
// This project is not part of the application solution and adds no sign-in bypass to the shipped application.
internal static class Program
{
    private static int result;
    [STAThread] public static int Main(string[] args)
    {
        AppBuilder.Configure<App>().UsePlatformDetect().AfterSetup(_ =>
            Dispatcher.UIThread.Post(async () => await Review())).StartWithClassicDesktopLifetime(args);
        return result;
    }
    private static async Task Review()
    {
        var lifetime = (IClassicDesktopStyleApplicationLifetime)Application.Current!.ApplicationLifetime!;
        var window = lifetime.MainWindow!;
        var admin = Environment.GetEnvironmentVariable("MWD_TEST_ADMIN") ?? throw new InvalidOperationException("Configure MWD_TEST_ADMIN for disposable UI fixtures.");
        var database = "mwd_ui_" + Guid.NewGuid().ToString("N");
        var created = false;
        try
        {
            await using (var con = new NpgsqlConnection(admin))
            {
                await con.OpenAsync(); await using var command = new NpgsqlCommand($"CREATE DATABASE \"{database}\"", con);
                await command.ExecuteNonQueryAsync(); created = true;
            }
            var config = new AppConfiguration(new NpgsqlConnectionStringBuilder(admin) { Database = database }.ConnectionString);
            var factory = new ConfiguredContextFactory(config);
            await using (var db = factory.CreateDbContext()) { await db.Database.MigrateAsync(); await DemoSeeder.SeedAsync(db); }
            var session = new Session(); var auth = new AuthenticationService(factory, session); var service = new WaterService(factory, session);
            await auth.LoginAsync("amara", DemoSeeder.Password);
            var leak = await service.SubmitAsync(new(null, ConcernCategory.WaterLeak, "Water leak at service line", "There seems to be a water leak near the service line in front of our house. Water has been flowing since this morning.", "12 Sample River Street, Maramag", "Please contact the account holder.", ""));
            await service.SubmitAsync(new(null, ConcernCategory.LowNoWaterSupply, "Low water supply in the morning", "Our fictional service location has experienced low water pressure in the morning.", "12 Sample River Street, Maramag", "", ""));
            var inquiry = await service.SubmitAsync(new(null, ConcernCategory.BillingPaymentInquiry, "Clarification on my water service bill", "Please explain the payment information on the fictional account statement.", "12 Sample River Street, Maramag", "", ""));
            await auth.LoginAsync("handler", DemoSeeder.Password);
            var d = await service.ConcernAsync(leak);
            await service.ProcessConcernAsync(leak, d.Row.Version, ConcernAction.Respond, "Thank you for reporting this. We have noted your concern and are reviewing the service location and next steps.", d.Row.Category);
            d = await service.ConcernAsync(leak);
            await service.ProcessConcernAsync(leak, d.Row.Version, ConcernAction.InternalNote, "Fictional staff-only location assessment. This must not appear in the client's timeline.", d.Row.Category);
            d = await service.ConcernAsync(inquiry);
            await service.ProcessConcernAsync(inquiry, d.Row.Version, ConcernAction.Respond, "We reviewed the fictional statement and explained the payment details.", d.Row.Category);
            d = await service.ConcernAsync(inquiry);
            await service.ProcessConcernAsync(inquiry, d.Row.Version, ConcernAction.Resolve, "The fictional statement question has been clarified with the account holder.", d.Row.Category);
            Directory.CreateDirectory("TestResults/ui-reference");
            window.WindowState = WindowState.Normal; window.Width = 1280; window.Height = 800;
            var login = new LoginViewModel(auth, new(factory, config), true, _ => { });
            window.Content = new LoginView { DataContext = login }; await Capture(window, "01-sign-in");
            var who = await auth.LoginAsync("amara", DemoSeeder.Password);
            var shell = new WorkspaceViewModel(service, who, new ConfirmationService(), true, () => { }, foundationOnly: false);
            window.Content = new WorkspaceView { DataContext = shell }; await Idle(shell.Page); await Capture(window, "02-client-overview");
            shell.Navigate("submit"); await Idle(shell.Page);
            var form = (SubmitViewModel)shell.Page; form.Category = form.Categories[0]; form.Subject = "Water leak at service line";
            form.Description = "There seems to be a water leak near the service line in front of our house. Water has been flowing since this morning.";
            await Capture(window, "03-client-submit");
            await form.ReviewCommand.ExecuteAsync(null); await Capture(window, "04-client-review");
            shell.Navigate("concerns"); await Idle(shell.Page); await Capture(window, "05-client-concerns");
            shell.OpenConcern(leak); await Idle(shell.Page); await Capture(window, "06-client-detail");
            shell.Navigate("accounts"); await Idle(shell.Page); await Capture(window, "07-client-account");
            who = await auth.LoginAsync("admin", DemoSeeder.Password);
            shell = new WorkspaceViewModel(service, who, new ConfirmationService(), true, () => { }, foundationOnly: false);
            window.Content = new WorkspaceView { DataContext = shell }; await Idle(shell.Page); await Capture(window, "08-office-overview");
            shell.Navigate("concerns"); await Idle(shell.Page); await Capture(window, "09-office-queue");
            shell.OpenConcern(leak); await Idle(shell.Page); await Capture(window, "10-office-detail");
            shell.Navigate("accounts"); await Idle(shell.Page); await Capture(window, "11-office-accounts");
            shell.Navigate("plumbers"); await Idle(shell.Page); await Capture(window, "12-office-resources");
            window.Width = 1024; window.Height = 700; shell.Navigate("submit"); await Idle(shell.Page); await Capture(window, "13-office-intake-1024");
            shell.Navigate("concerns"); await Idle(shell.Page); await Capture(window, "14-office-queue-1024");
            window.Width = 1280; window.Height = 800;
            who = await auth.LoginAsync("viewer", DemoSeeder.Password);
            shell = new WorkspaceViewModel(service, who, new ConfirmationService(), true, () => { }, foundationOnly: false);
            window.Content = new WorkspaceView { DataContext = shell }; await Idle(shell.Page);
            shell.OpenConcern(leak); await Idle(shell.Page);
            if (((ConcernDetailViewModel)shell.Page).CanRespond) throw new InvalidOperationException("Read-only office editor must be hidden.");
            await Capture(window, "15-read-only-office");
            who = await auth.LoginAsync("benito", DemoSeeder.Password);
            shell = new WorkspaceViewModel(service, who, new ConfirmationService(), true, () => { }, foundationOnly: false);
            window.Content = new WorkspaceView { DataContext = shell }; await Idle(shell.Page);
            shell.Navigate("concerns"); await Idle(shell.Page);
            if (!((ConcernsViewModel)shell.Page).Empty) throw new InvalidOperationException("Another client's concerns appeared in the empty client list.");
            await Capture(window, "16-client-empty");
            Console.WriteLine("Rendered 16 production UI states against disposable persisted fixtures.");
        }
        catch (Exception ex) { result = 1; Console.Error.WriteLine(ex); }
        finally
        {
            if (created)
            {
                await using var con = new NpgsqlConnection(admin); await con.OpenAsync();
                await using var cmd = new NpgsqlCommand($"DROP DATABASE \"{database}\" WITH (FORCE)", con); await cmd.ExecuteNonQueryAsync();
            }
            lifetime.Shutdown(result);
        }
    }
    private static async Task Idle(ViewModelBase vm)
    {
        var until = DateTime.UtcNow.AddSeconds(15);
        while (vm.IsBusy && DateTime.UtcNow < until) await Task.Delay(20);
        if (vm.IsBusy || !string.IsNullOrEmpty(vm.Error)) throw new InvalidOperationException("UI operation failed: " + vm.Error);
    }
    private static async Task Capture(Window window, string name)
    {
        await Task.Delay(350); // Let the real bindings, layout and 220ms transition finish.
        var root = (Control)window.Content!;
        using var bitmap = new RenderTargetBitmap(new PixelSize((int)root.Bounds.Width, (int)root.Bounds.Height), new Vector(96, 96));
        bitmap.Render(root); bitmap.Save(Path.Combine("TestResults/ui-reference", name + ".png"), new PngBitmapEncoderOptions());
        foreach (var combo in root.GetVisualDescendants().OfType<ComboBox>())
        {
            Console.WriteLine($"  Combo {combo.Items.Count} items; selected: {combo.SelectedItem}");
            if (combo.DataContext is ConcernDetailViewModel detail)
            {
                Console.WriteLine($"  Detail action: {detail.Action}; valid choices: {detail.AvailableActions.Length}");
                if (Avalonia.Automation.AutomationProperties.GetName(combo) == "Office action" && combo.SelectedItem == null && detail.AvailableActions.Length > 0)
                    throw new InvalidOperationException("The office action selector lost its active selection.");
            }
        }
        Console.WriteLine("Rendered " + name);
    }
}
