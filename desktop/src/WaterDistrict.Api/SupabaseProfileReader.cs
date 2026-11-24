using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using WaterDistrict.Application;
using WaterDistrict.Domain;

namespace WaterDistrict.Api;

public sealed class SupabaseProfileReader(HttpClient client) : IProfileReader
{
    public async Task<AppProfile?> FindAsync(Guid userId, string bearerToken, CancellationToken cancellationToken)
    {
        var rows = await ReadAsync($"profiles?select=user_id,display_name,role,active&user_id=eq.{userId:D}&limit=2",
            bearerToken, cancellationToken);
        if (rows.Count > 1)
            throw new DependencyUnavailableException("The profile data needs administrator review.");
        return rows.SingleOrDefault();
    }

    public Task<IReadOnlyList<AppProfile>> ListStaffAsync(string bearerToken, CancellationToken cancellationToken) =>
        ReadAsync("profiles?select=user_id,display_name,role,active&active=eq.true&role=in.(admin,staff)&order=display_name",
            bearerToken, cancellationToken);

    private async Task<IReadOnlyList<AppProfile>> ReadAsync(string path, string token, CancellationToken cancellationToken)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, path);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var response = await client.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode)
                throw new DependencyUnavailableException("Profile access is unavailable. Check Supabase permissions and connectivity.");
            var rows = await response.Content.ReadFromJsonAsync<List<ProfileRow>>(cancellationToken);
            if (rows is null || rows.Any(row => row.UserId == Guid.Empty || string.IsNullOrWhiteSpace(row.Role) || row.Active is null))
                throw new DependencyUnavailableException("The profile service returned incomplete data.");
            return rows.Select(row => new AppProfile { UserId = row.UserId, DisplayName = row.DisplayName ?? "",
                Role = row.Role!, Active = row.Active!.Value }).ToArray();
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        { throw new DependencyUnavailableException("The profile service timed out. Try again."); }
        catch (Exception exception) when (exception is HttpRequestException or JsonException or NotSupportedException)
        { throw new DependencyUnavailableException("The profile service is unavailable or returned invalid data."); }
    }

    private sealed record ProfileRow(
        [property: JsonPropertyName("user_id")] Guid UserId,
        [property: JsonPropertyName("display_name")] string? DisplayName,
        [property: JsonPropertyName("role")] string? Role,
        [property: JsonPropertyName("active")] bool? Active);
}
