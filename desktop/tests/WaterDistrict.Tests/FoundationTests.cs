using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using WaterDistrict.Infrastructure;

namespace WaterDistrict.Tests;

public sealed class FoundationTests
{
    [Fact]
    public async Task Unconfigured_database_reports_unavailable_without_throwing()
    {
        var status = await new DatabaseProbe(null).CheckAsync(TestContext.Current.CancellationToken);
        Assert.Equal("unconfigured", status.Status);
    }

    [Fact]
    public async Task Invalid_connection_does_not_expose_connection_details()
    {
        var status = await new DatabaseProbe("invalid-secret-connection").CheckAsync(TestContext.Current.CancellationToken);
        Assert.Equal("unavailable", status.Status);
        Assert.DoesNotContain("secret", status.Message);
    }

    [Fact]
    public async Task Api_is_alive_but_not_database_ready_when_probe_is_unconfigured()
    {
        await using var factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureServices(services =>
            {
                // Local settings are loaded during startup. This HTTP contract test must
                // use its own probe rather than connecting to a developer's database.
                services.RemoveAll<DatabaseProbe>();
                services.AddSingleton(new DatabaseProbe(null));
            }));
        using var client = factory.CreateClient();
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/health", TestContext.Current.CancellationToken)).StatusCode);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await client.GetAsync("/health/ready", TestContext.Current.CancellationToken)).StatusCode);
    }
}
