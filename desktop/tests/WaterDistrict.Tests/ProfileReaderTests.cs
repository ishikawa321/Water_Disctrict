using System.Net;
using System.Net.Http.Json;
using WaterDistrict.Api;
using WaterDistrict.Application;

namespace WaterDistrict.Tests;

public sealed class ProfileReaderTests
{
    [Fact]
    public async Task Lookup_uses_verified_subject_and_caller_token()
    {
        var userId = Guid.NewGuid();
        var reader = Reader(request =>
        {
            Assert.Equal("test-token", request.Headers.Authorization!.Parameter);
            Assert.Contains($"user_id=eq.{userId:D}", request.RequestUri!.Query);
            return Json(new[] { new { user_id = userId, display_name = "Staff A", role = "staff", active = true } });
        });
        var profile = await reader.FindAsync(userId, "test-token", TestContext.Current.CancellationToken);
        Assert.Equal(userId, profile!.UserId);
        Assert.True(profile.Active);
        Assert.Equal("staff", profile.Role);
    }

    [Fact]
    public async Task Invisible_profile_is_missing_instead_of_fabricated()
    {
        var reader = Reader(_ => Json(Array.Empty<object>()));
        Assert.Null(await reader.FindAsync(Guid.NewGuid(), "token", TestContext.Current.CancellationToken));
    }

    [Theory]
    [InlineData("null")]
    [InlineData("not-json")]
    [InlineData("[{\"role\":\"admin\"}]")]
    public async Task Invalid_profile_response_is_a_dependency_failure(string content)
    {
        var reader = Reader(_ => new(HttpStatusCode.OK) { Content = new StringContent(content, System.Text.Encoding.UTF8, "application/json") });
        await Assert.ThrowsAsync<DependencyUnavailableException>(() => reader.FindAsync(Guid.NewGuid(), "token", TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task Denied_table_permission_is_not_an_empty_success()
    {
        var reader = Reader(_ => new(HttpStatusCode.Forbidden));
        await Assert.ThrowsAsync<DependencyUnavailableException>(() => reader.FindAsync(Guid.NewGuid(), "token", TestContext.Current.CancellationToken));
    }

    private static HttpResponseMessage Json<T>(T value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static SupabaseProfileReader Reader(Func<HttpRequestMessage, HttpResponseMessage> response) =>
        new(new HttpClient(new Handler(response)) { BaseAddress = new("https://test.supabase.co/rest/v1/") });
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> response) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => Task.FromResult(response(request));
    }
}
