using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WaterDistrict.Application;

public interface IDesktopSessionClient
{
    bool IsAuthenticated { get; }
    Task<SessionProfile> SignInAsync(string email, string password, CancellationToken cancellationToken = default);
    Task<SessionProfile> RefreshProfileAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyList<StaffMember>> GetStaffAsync(CancellationToken cancellationToken = default);
    Task SignOutAsync();
}

public sealed class SessionClientException(string message, bool requiresSignIn = false) : Exception(message)
{
    public bool RequiresSignIn { get; } = requiresSignIn;
}

// Access tokens stay in memory. No password/refresh token/session file is persisted.
public sealed class DesktopSessionClient(HttpClient auth, HttpClient api, TimeProvider? clock = null) : IDesktopSessionClient
{
    private readonly TimeProvider time = clock ?? TimeProvider.System;
    private string? accessToken;
    private DateTimeOffset expiresAt;
    public bool IsAuthenticated => accessToken is not null && time.GetUtcNow() < expiresAt;

    public async Task<SessionProfile> SignInAsync(string email, string password, CancellationToken cancellationToken = default)
    {
        await SignOutAsync();
        try
        {
            using var response = await auth.PostAsJsonAsync("token?grant_type=password", new { email = email.Trim(), password }, cancellationToken);
            if (!response.IsSuccessStatusCode)
                throw new SessionClientException(response.StatusCode == HttpStatusCode.TooManyRequests
                    ? "Too many sign-in attempts. Wait a moment and try again."
                    : "Sign-in failed. Check your email and password, and confirm your email is verified.");
            var result = await response.Content.ReadFromJsonAsync<AuthResponse>(cancellationToken);
            if (string.IsNullOrWhiteSpace(result?.AccessToken) || result.ExpiresIn <= 0)
                throw new SessionClientException("The sign-in service returned an incomplete session. Try again.");
            accessToken = result.AccessToken;
            expiresAt = time.GetUtcNow().AddSeconds(result.ExpiresIn);
            return await RefreshProfileAsync(cancellationToken);
        }
        catch (Exception exception) when (exception is HttpRequestException or JsonException or TaskCanceledException)
        {
            await SignOutAsync();
            throw new SessionClientException("Could not complete sign-in. Check the API and internet connection, then try again.");
        }
        catch
        {
            await SignOutAsync();
            throw;
        }
    }

    public Task<SessionProfile> RefreshProfileAsync(CancellationToken cancellationToken = default) =>
        ReadApiAsync<SessionProfile>("api/session", cancellationToken);

    public async Task<IReadOnlyList<StaffMember>> GetStaffAsync(CancellationToken cancellationToken = default) =>
        await ReadApiAsync<StaffMember[]>("api/admin/staff", cancellationToken);

    private async Task<T> ReadApiAsync<T>(string path, CancellationToken cancellationToken)
    {
        if (!IsAuthenticated)
        {
            accessToken = null;
            throw new SessionClientException("Your session has ended. Sign in again.", requiresSignIn: true);
        }
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, path);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
            using var response = await api.SendAsync(request, cancellationToken);
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            {
                await SignOutAsync();
                throw new SessionClientException(response.StatusCode == HttpStatusCode.Unauthorized
                    ? "Your session has ended. Sign in again."
                    : "Access denied. An active Admin or Staff profile with permission is required.", requiresSignIn: true);
            }
            if (!response.IsSuccessStatusCode)
                throw new SessionClientException("The office service is unavailable. Check connectivity and try again.");
            return await response.Content.ReadFromJsonAsync<T>(cancellationToken)
                ?? throw new SessionClientException("The office service returned an incomplete response.");
        }
        catch (Exception exception) when (exception is HttpRequestException or JsonException or TaskCanceledException)
        { throw new SessionClientException("Cannot reach the office service. Check the API and internet connection, then retry."); }
    }

    public async Task SignOutAsync()
    {
        var token = accessToken;
        accessToken = null;
        expiresAt = default;
        if (token is null) return;
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            using var request = new HttpRequestMessage(HttpMethod.Post, "logout?scope=local");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var response = await auth.SendAsync(request, timeout.Token);
        }
        catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException)
        { /* Local sign-out succeeds even if remote revocation is unavailable. */ }
    }

    private sealed record AuthResponse(
        [property: JsonPropertyName("access_token")] string? AccessToken,
        [property: JsonPropertyName("expires_in")] int ExpiresIn);
}
