using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using WaterDistrict.Application;

namespace WaterDistrict.Tests;

public sealed class DesktopSessionClientTests
{
    private static readonly SessionProfile Profile = new(Guid.NewGuid(), "Office user", "admin", ["staff.read"]);

    [Fact]
    public async Task Sign_in_sends_credentials_to_auth_and_only_bearer_to_api()
    {
        var auth = new Handler(async request =>
        {
            Assert.Equal("/auth/v1/token", request.RequestUri!.AbsolutePath);
            Assert.Equal("?grant_type=password", request.RequestUri.Query);
            var payload = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(TestContext.Current.CancellationToken));
            Assert.Equal("admin@example.com", payload.RootElement.GetProperty("email").GetString());
            Assert.Equal("test-password", payload.RootElement.GetProperty("password").GetString());
            return Json(new { access_token = "test-token", expires_in = 3600 });
        });
        var api = new Handler(request =>
        {
            Assert.Equal("Bearer", request.Headers.Authorization!.Scheme);
            Assert.Equal("test-token", request.Headers.Authorization.Parameter);
            Assert.Null(request.Content);
            return Task.FromResult(Json(Profile));
        });
        var client = Create(auth, api);
        Assert.Equal(Profile, await client.SignInAsync(" admin@example.com ", "test-password", TestContext.Current.CancellationToken) with { Permissions = Profile.Permissions });
        Assert.True(client.IsAuthenticated);
    }

    [Fact]
    public async Task Failed_password_does_not_contact_api_or_keep_session()
    {
        var auth = new Handler(_ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.BadRequest)));
        var api = new Handler(_ => throw new InvalidOperationException("API should not be called"));
        var client = Create(auth, api);
        var exception = await Assert.ThrowsAsync<SessionClientException>(() => client.SignInAsync("user@example.com", "wrong", TestContext.Current.CancellationToken));
        Assert.Contains("Sign-in failed", exception.Message);
        Assert.False(client.IsAuthenticated);
    }

    [Fact]
    public async Task Consumer_rejection_clears_and_revokes_obtained_session()
    {
        var revocations = 0;
        var auth = new Handler(request =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("logout"))
            {
                revocations++;
                Assert.Equal("test-token", request.Headers.Authorization!.Parameter);
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NoContent));
            }
            return Task.FromResult(Json(new { access_token = "test-token", expires_in = 3600 }));
        });
        var api = new Handler(_ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden)));
        var client = Create(auth, api);
        var exception = await Assert.ThrowsAsync<SessionClientException>(() => client.SignInAsync("consumer@example.com", "password", TestContext.Current.CancellationToken));
        Assert.True(exception.RequiresSignIn);
        Assert.False(client.IsAuthenticated);
        Assert.Equal(1, revocations);
    }

    [Fact]
    public async Task Logout_clears_local_session_when_remote_service_is_offline()
    {
        var auth = new Handler(request => request.RequestUri!.AbsolutePath.EndsWith("logout")
            ? throw new HttpRequestException("offline")
            : Task.FromResult(Json(new { access_token = "test-token", expires_in = 3600 })));
        var client = Create(auth, new Handler(_ => Task.FromResult(Json(Profile))));
        await client.SignInAsync("admin@example.com", "password", TestContext.Current.CancellationToken);
        await client.SignOutAsync();
        Assert.False(client.IsAuthenticated);
        await Assert.ThrowsAsync<SessionClientException>(() => client.RefreshProfileAsync(TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task Expired_session_requires_sign_in_without_sending_stale_token()
    {
        var clock = new TestClock();
        var reads = 0;
        var client = Create(
            new Handler(_ => Task.FromResult(Json(new { access_token = "token", expires_in = 60 }))),
            new Handler(_ => { reads++; return Task.FromResult(Json(Profile)); }), clock);
        await client.SignInAsync("admin@example.com", "password", TestContext.Current.CancellationToken);
        clock.Now = clock.Now.AddMinutes(2);
        var exception = await Assert.ThrowsAsync<SessionClientException>(() => client.RefreshProfileAsync(TestContext.Current.CancellationToken));
        Assert.True(exception.RequiresSignIn);
        Assert.Equal(1, reads);
        Assert.False(client.IsAuthenticated);
    }

    [Fact]
    public async Task Network_failure_after_password_success_does_not_keep_hidden_session()
    {
        var auth = new Handler(_ => Task.FromResult(Json(new { access_token = "token", expires_in = 3600 })));
        var api = new Handler(_ => throw new HttpRequestException("internal-url-secret"));
        var client = Create(auth, api);
        var exception = await Assert.ThrowsAsync<SessionClientException>(() => client.SignInAsync("admin@example.com", "password", TestContext.Current.CancellationToken));
        Assert.DoesNotContain("secret", exception.Message);
        Assert.False(client.IsAuthenticated);
    }

    private static DesktopSessionClient Create(Handler auth, Handler api, TimeProvider? clock = null) => new(
        new HttpClient(auth) { BaseAddress = new("https://auth.example/auth/v1/") },
        new HttpClient(api) { BaseAddress = new("https://office.example/") }, clock);
    private static HttpResponseMessage Json<T>(T content) => new(HttpStatusCode.OK) { Content = JsonContent.Create(content) };
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => send(request);
    }
    private sealed class TestClock : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => Now;
    }
}
