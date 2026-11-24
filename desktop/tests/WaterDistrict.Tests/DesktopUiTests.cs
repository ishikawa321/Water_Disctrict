using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Threading;
using Avalonia.VisualTree;
using WaterDistrict.Application;
using WaterDistrict.Desktop;
using WaterDistrict.Desktop.ViewModels;
using WaterDistrict.Desktop.Views;

[assembly: AvaloniaTestApplication(typeof(WaterDistrict.Tests.TestAppBuilder))]

namespace WaterDistrict.Tests;

public static class TestAppBuilder
{
    public static AppBuilder BuildAvaloniaApp() => AppBuilder.Configure<App>().UseSkia().WithInterFont()
        .UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false });
}

public sealed class DesktopUiTests
{
    [AvaloniaFact]
    public async Task Invalid_input_does_not_send_credentials()
    {
        var sessions = new FakeSession();
        var model = new MainViewModel(sessions) { Email = "not-email", Password = "password" };
        await model.SignInCommand.ExecuteAsync(null);
        Assert.Equal(0, sessions.SignIns);
        Assert.True(model.IsSignedOut);
        Assert.Contains("valid email", model.Message);
    }

    [AvaloniaTheory]
    [InlineData("admin", true)]
    [InlineData("staff", false)]
    public async Task Workspace_exposes_only_the_correct_role_controls(string role, bool expectedAdmin)
    {
        var sessions = new FakeSession(role);
        var model = new MainViewModel(sessions) { Email = "office@example.com", Password = "test-password" };
        var window = new MainWindow { DataContext = model };
        window.Show();
        await model.SignInCommand.ExecuteAsync(null);
        Dispatcher.UIThread.RunJobs();
        Assert.True(model.IsSignedIn);
        Assert.Equal("", model.Password);
        Assert.Equal(expectedAdmin, model.IsAdmin);
        var directory = window.GetVisualDescendants().OfType<Button>().Single(button => Equals(button.Content, "Staff directory"));
        Assert.Equal(expectedAdmin, directory.IsVisible);
        Capture(window, role + "-workspace");
        await model.SignOutCommand.ExecuteAsync(null);
        Assert.True(model.IsSignedOut);
        Assert.Empty(model.Staff);
        Assert.False(model.IsAdmin);
        window.Close();
    }

    [AvaloniaFact]
    public async Task Revoked_profile_clears_privileged_workspace_and_loaded_directory()
    {
        var sessions = new FakeSession();
        var model = new MainViewModel(sessions) { Email = "office@example.com", Password = "test-password" };
        await model.SignInCommand.ExecuteAsync(null);
        await model.LoadStaffCommand.ExecuteAsync(null);
        Assert.Single(model.Staff);
        sessions.Revoked = true;
        await model.RefreshAccessCommand.ExecuteAsync(null);
        Assert.True(model.IsSignedOut);
        Assert.False(model.ShowDirectory);
        Assert.Empty(model.Staff);
        Assert.Contains("Access denied", model.Message);
    }

    [AvaloniaFact]
    public void Sign_in_renders_at_minimum_window_size()
    {
        var window = new MainWindow { Width = 850, Height = 650, DataContext = new MainViewModel(new FakeSession()) };
        window.Show();
        Dispatcher.UIThread.RunJobs();
        var password = window.GetVisualDescendants().OfType<TextBox>().Single(box => box.PasswordChar != default);
        Assert.True(password.Bounds.Width > 100);
        Assert.True(password.Bounds.Height > 20);
        Capture(window, "sign-in-minimum");
        window.Close();
    }

    private static void Capture(Window window, string name)
    {
        AvaloniaHeadlessPlatform.ForceRenderTimerTick();
        using var frame = window.CaptureRenderedFrame();
        Assert.NotNull(frame);
        var folder = Path.Combine(AppContext.BaseDirectory, "artifacts", "ui");
        Directory.CreateDirectory(folder);
        frame!.Save(Path.Combine(folder, name + ".png"), Avalonia.Media.Imaging.PngBitmapEncoderOptions.Default);
    }

    private sealed class FakeSession(string role = "admin") : IDesktopSessionClient
    {
        private readonly SessionProfile profile = new(Guid.NewGuid(), "Office Test User", role, []);
        public bool IsAuthenticated { get; private set; }
        public bool Revoked { get; set; }
        public int SignIns { get; private set; }
        public Task<SessionProfile> SignInAsync(string email, string password, CancellationToken cancellationToken = default)
        { SignIns++; IsAuthenticated = true; return Task.FromResult(profile); }
        public Task<SessionProfile> RefreshProfileAsync(CancellationToken cancellationToken = default) => Revoked
            ? throw new SessionClientException("Access denied. Sign in again.", true) : Task.FromResult(profile);
        public Task<IReadOnlyList<StaffMember>> GetStaffAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<StaffMember>>([new(profile.UserId, profile.DisplayName, profile.Role)]);
        public Task SignOutAsync() { IsAuthenticated = false; return Task.CompletedTask; }
    }
}
