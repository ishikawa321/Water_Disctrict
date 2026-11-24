using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.AspNetCore.Hosting;
using WaterDistrict.Infrastructure;

namespace WaterDistrict.Tests;

public sealed class FoundationTests
{
    [Fact]
    public async Task Unconfigured_database_reports_unavailable_without_throwing()
    {
        var status = await new DatabaseProbe(null).CheckAsync(CancellationToken.None);
        Assert.Equal("unconfigured", status.Status);
    }

    [Fact]
    public async Task Invalid_connection_does_not_expose_connection_details()
    {
        var status = await new DatabaseProbe("invalid-secret-connection").CheckAsync(CancellationToken.None);
        Assert.Equal("unavailable", status.Status);
        Assert.DoesNotContain("secret", status.Message);
    }

    [Fact]
    public async Task Api_is_alive_but_not_database_ready_without_configuration()
    {
        await using var factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(
                new Dictionary<string, string?> { ["ConnectionStrings:WaterDistrict"] = "" })));
        using var client = factory.CreateClient();
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/health")).StatusCode);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await client.GetAsync("/health/ready")).StatusCode);
    }
}
