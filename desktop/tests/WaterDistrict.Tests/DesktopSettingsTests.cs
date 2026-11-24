using Microsoft.Extensions.Configuration;
using WaterDistrict.Desktop;

namespace WaterDistrict.Tests;

public sealed class DesktopSettingsTests
{
    [Theory]
    [InlineData("http://remote.example/")]
    [InlineData("https://user:password@office.example/")]
    [InlineData("https://office.example/?token=secret")]
    public void Credentials_are_not_sent_to_insecure_or_ambiguous_api_addresses(string api)
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> {
            ["Supabase:Url"] = "https://test.supabase.co", ["Supabase:PublishableKey"] = "public-key", ["Api:BaseUrl"] = api
        }).Build();
        Assert.Throws<InvalidOperationException>(() => DesktopSettings.Load(configuration));
    }
}
