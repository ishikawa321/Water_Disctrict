using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using WaterDistrict.Application;
using WaterDistrict.Domain;

namespace WaterDistrict.Tests;

public sealed class AuthorizationTests
{
    [Fact]
    public async Task Anonymous_requests_are_challenged()
    {
        await using var app = new AuthFactory("admin");
        using var client = app.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/session")).StatusCode);
        Assert.Equal(0, app.Profiles.ReadCount);
    }

    [Theory]
    [InlineData("admin")]
    [InlineData("staff")]
    public async Task Active_office_profile_receives_its_database_role(string role)
    {
        await using var app = new AuthFactory(role);
        using var client = app.AuthenticatedClient();
        var response = await client.GetAsync("/api/session");
        response.EnsureSuccessStatusCode();
        var session = await response.Content.ReadFromJsonAsync<SessionProfile>();
        Assert.Equal(role, session!.Role);
        Assert.Equal(app.UserId, session.UserId);
        Assert.Equal(role == "admin", session.Permissions.Contains("staff.read"));
    }

    [Theory]
    [InlineData("client", true)]
    [InlineData("admin", false)]
    [InlineData("staff", false)]
    [InlineData("unknown", true)]
    public async Task Consumer_inactive_and_unknown_roles_cannot_access_desktop(string role, bool active)
    {
        await using var app = new AuthFactory(role, active);
        using var client = app.AuthenticatedClient(claimedRole: "admin");
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/api/session")).StatusCode);
    }

    [Fact]
    public async Task Missing_or_mismatched_profile_is_rejected()
    {
        await using var app = new AuthFactory("admin");
        using var client = app.AuthenticatedClient();
        app.Profiles.Profile = null;
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/api/session")).StatusCode);
        app.Profiles.Profile = new() { UserId = Guid.NewGuid(), Active = true, Role = "admin" };
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/api/session")).StatusCode);
    }

    [Fact]
    public async Task Staff_cannot_access_admin_directory_even_with_admin_claim()
    {
        await using var app = new AuthFactory("staff");
        using var client = app.AuthenticatedClient(claimedRole: "admin");
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/api/admin/staff")).StatusCode);
    }

    [Fact]
    public async Task Admin_directory_is_filtered_and_profile_changes_apply_next_request()
    {
        await using var app = new AuthFactory("admin");
        using var client = app.AuthenticatedClient();
        var directory = await client.GetFromJsonAsync<StaffMember[]>("/api/admin/staff");
        Assert.Single(directory!);
        Assert.Equal(app.UserId, directory![0].UserId);
        app.Profiles.Profile!.Active = false;
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/api/session")).StatusCode);
    }

    [Theory]
    [InlineData("issuer")]
    [InlineData("audience")]
    [InlineData("expired")]
    [InlineData("signature")]
    [InlineData("malformed")]
    public async Task Invalid_tokens_never_reach_profile_lookup(string fault)
    {
        await using var app = new AuthFactory("admin");
        using var client = app.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Bearer", app.Token(fault: fault));
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/session")).StatusCode);
        Assert.Equal(0, app.Profiles.ReadCount);
    }

    [Fact]
    public async Task Dependency_failure_is_not_an_authorization_success()
    {
        await using var app = new AuthFactory("admin");
        app.Profiles.Fail = true;
        using var client = app.AuthenticatedClient();
        var response = await client.GetAsync("/api/session");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Contains("unavailable", await response.Content.ReadAsStringAsync());
    }

    private sealed class AuthFactory : WebApplicationFactory<Program>
    {
        private const string Issuer = "https://kaeespcylucvsazfdaks.supabase.co/auth/v1";
        private readonly ECDsa key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        public Guid UserId { get; } = Guid.NewGuid();
        public FakeProfiles Profiles { get; }
        public AuthFactory(string role, bool active = true)
        {
            Profiles = new() { Profile = new() { UserId = UserId, DisplayName = "Test operator", Role = role, Active = active } };
        }
        protected override void ConfigureWebHost(IWebHostBuilder builder) => builder.ConfigureServices(services =>
        {
            services.RemoveAll<IProfileReader>();
            services.AddSingleton<IProfileReader>(Profiles);
            services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
            {
                var configuration = new OpenIdConnectConfiguration { Issuer = Issuer };
                configuration.SigningKeys.Add(new ECDsaSecurityKey(key) { KeyId = "test-key" });
                options.ConfigurationManager = new StaticConfigurationManager<OpenIdConnectConfiguration>(configuration);
            });
        });
        public HttpClient AuthenticatedClient(string claimedRole = "authenticated")
        {
            var client = CreateClient();
            client.DefaultRequestHeaders.Authorization = new("Bearer", Token(claimedRole: claimedRole));
            return client;
        }
        public string Token(string? fault = null, string claimedRole = "authenticated")
        {
            if (fault == "malformed") return "not.a.valid.token";
            using var wrongKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            var securityKey = new ECDsaSecurityKey(fault == "signature" ? wrongKey : key) { KeyId = "test-key" };
            var token = new JwtSecurityToken(
                fault == "issuer" ? "https://other-project.invalid/auth/v1" : Issuer,
                fault == "audience" ? "other-client" : "authenticated",
                [new Claim("sub", UserId.ToString()), new Claim("role", claimedRole)],
                notBefore: DateTime.UtcNow.AddHours(-2),
                expires: fault == "expired" ? DateTime.UtcNow.AddHours(-1) : DateTime.UtcNow.AddMinutes(10),
                signingCredentials: new SigningCredentials(securityKey, SecurityAlgorithms.EcdsaSha256));
            return new JwtSecurityTokenHandler().WriteToken(token);
        }
    }

    private sealed class FakeProfiles : IProfileReader
    {
        public AppProfile? Profile { get; set; }
        public bool Fail { get; set; }
        public int ReadCount { get; private set; }
        public Task<AppProfile?> FindAsync(Guid userId, string bearerToken, CancellationToken cancellationToken)
        {
            ReadCount++;
            if (Fail) throw new DependencyUnavailableException("Profile service unavailable.");
            return Task.FromResult(Profile);
        }
        public Task<IReadOnlyList<AppProfile>> ListStaffAsync(string bearerToken, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<AppProfile>>([Profile!, new() { UserId = Guid.NewGuid(), Active = true, Role = "client" }]);
    }
}
