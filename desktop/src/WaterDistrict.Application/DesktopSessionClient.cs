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
public sealed class DesktopSessionClient(HttpClient auth, HttpClient api, TimeProvider? clock = null) : IDesktopSessionClient, IWorkflowClient, IOfficeClient
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

    private Task<T> ReadApiAsync<T>(string path, CancellationToken token) => SendApiAsync<T>(HttpMethod.Get,path,null,token);

    private async Task<T> SendApiAsync<T>(HttpMethod method, string path, object? input, CancellationToken cancellationToken)
    {
        if (!IsAuthenticated)
        {
            accessToken = null;
            throw new SessionClientException("Your session has ended. Sign in again.", requiresSignIn: true);
        }
        try
        {
            using var request = new HttpRequestMessage(method, path);
            if(input is not null) request.Content = JsonContent.Create(input);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
            using var response = await api.SendAsync(request, cancellationToken);
            if (response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.Forbidden && path == "api/session")
            {
                await SignOutAsync();
                throw new SessionClientException(response.StatusCode == HttpStatusCode.Unauthorized
                    ? "Your session has ended. Sign in again."
                    : "Access denied. An active Admin or Staff profile with permission is required.", requiresSignIn: true);
            }
            if (!response.IsSuccessStatusCode)
            {
                string? detail = null;
                try { detail = (await response.Content.ReadFromJsonAsync<ErrorResponse>(cancellationToken))?.Detail; }
                catch(JsonException) { }
                throw new SessionClientException(detail ?? (response.StatusCode == HttpStatusCode.Forbidden
                    ? "You do not have permission for that operation."
                    : "The office service is unavailable. Refresh before retrying."));
            }
            return await response.Content.ReadFromJsonAsync<T>(cancellationToken)
                ?? throw new SessionClientException("The office service returned an incomplete response.");
        }
        catch (Exception exception) when (exception is HttpRequestException or JsonException or TaskCanceledException)
        { throw new SessionClientException(method == HttpMethod.Get
            ? "Cannot reach the office service. Check the API and internet connection, then retry."
            : "The saved result could not be confirmed. Refresh the list before retrying; your draft has been kept."); }
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

    public async Task<IReadOnlyList<AccountOption>> AccountsAsync(string? search=null,CancellationToken token=default) => await ReadApiAsync<AccountOption[]>("api/workflow/accounts?search="+Uri.EscapeDataString(search??""),token);
    public async Task<IReadOnlyList<StaffMember>> AssigneesAsync(CancellationToken token=default) => await ReadApiAsync<StaffMember[]>("api/workflow/assignees",token);
    public async Task<IReadOnlyList<ConcernRecord>> ConcernsAsync(string? search=null,string? status=null,CancellationToken token=default) => await ReadApiAsync<ConcernRecord[]>("api/workflow/concerns?search="+Uri.EscapeDataString(search??"")+"&status="+Uri.EscapeDataString(status??""),token);
    public Task<ConcernRecord> ConcernAsync(Guid id,CancellationToken token=default) => ReadApiAsync<ConcernRecord>($"api/workflow/concerns/{id}",token);
    public Task<ConcernRecord> CreateConcernAsync(CreateConcern input,CancellationToken token=default) => SendApiAsync<ConcernRecord>(HttpMethod.Post,"api/workflow/concerns",input,token);
    public Task<ConcernRecord> ReviewConcernAsync(Guid id,ReviewConcern input,CancellationToken token=default) => SendApiAsync<ConcernRecord>(HttpMethod.Put,$"api/workflow/concerns/{id}/review",input,token);
    public async Task<IReadOnlyList<TicketRecord>> TicketsAsync(string? search=null,string? status=null,CancellationToken token=default) => await ReadApiAsync<TicketRecord[]>("api/workflow/tickets?search="+Uri.EscapeDataString(search??"")+"&status="+Uri.EscapeDataString(status??""),token);
    public Task<TicketDetails> TicketAsync(Guid id,CancellationToken token=default) => ReadApiAsync<TicketDetails>($"api/workflow/tickets/{id}",token);
    public Task<TicketDetails> CreateTicketAsync(CreateTicket input,CancellationToken token=default) => SendApiAsync<TicketDetails>(HttpMethod.Post,"api/workflow/tickets",input,token);
    public Task<TicketDetails> UpdateTicketAsync(Guid id,UpdateTicket input,CancellationToken token=default) => SendApiAsync<TicketDetails>(HttpMethod.Put,$"api/workflow/tickets/{id}",input,token);
    public Task<OfficeSummary> SummaryAsync(CancellationToken token=default)=>ReadApiAsync<OfficeSummary>("api/office/summary",token);
    public async Task<IReadOnlyList<OfficeAccount>> OfficeAccountsAsync(CancellationToken token=default)=>await ReadApiAsync<OfficeAccount[]>("api/office/accounts",token);
    public Task<OfficeAccount> AddAccountAsync(AddOfficeAccount input,CancellationToken token=default)=>SendApiAsync<OfficeAccount>(HttpMethod.Post,"api/office/accounts",input,token);
    public async Task<IReadOnlyList<OfficeBill>> BillsAsync(CancellationToken token=default)=>await ReadApiAsync<OfficeBill[]>("api/office/bills",token);
    public Task<OfficeBill> AddBillAsync(AddOfficeBill input,CancellationToken token=default)=>SendApiAsync<OfficeBill>(HttpMethod.Post,"api/office/bills",input,token);
    public async Task<IReadOnlyList<OfficePayment>> PaymentsAsync(CancellationToken token=default)=>await ReadApiAsync<OfficePayment[]>("api/office/payments",token);
    public Task<OfficePayment> AddPaymentAsync(AddOfficePayment input,CancellationToken token=default)=>SendApiAsync<OfficePayment>(HttpMethod.Post,"api/office/payments",input,token);
    public async Task<IReadOnlyList<OfficeAnnouncement>> AnnouncementsAsync(CancellationToken token=default)=>await ReadApiAsync<OfficeAnnouncement[]>("api/office/announcements",token);
    public Task<OfficeAnnouncement> SaveAnnouncementAsync(Guid? id,SaveOfficeAnnouncement input,CancellationToken token=default)=>SendApiAsync<OfficeAnnouncement>(id is null?HttpMethod.Post:HttpMethod.Put,"api/office/announcements"+(id is null?"":"/"+id),input,token);
    private sealed record ErrorResponse(string? Detail);

    private sealed record AuthResponse(
        [property: JsonPropertyName("access_token")] string? AccessToken,
        [property: JsonPropertyName("expires_in")] int ExpiresIn);
}
