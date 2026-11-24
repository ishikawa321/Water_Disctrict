using Microsoft.Extensions.Configuration;

namespace WaterDistrict.Desktop;

public sealed record DesktopSettings(Uri SupabaseUrl, string PublishableKey, Uri ApiUrl)
{
    public static DesktopSettings Load(IConfiguration configuration)
    {
        var supabase = configuration["Supabase:Url"];
        var api = configuration["Api:BaseUrl"];
        var key = configuration["Supabase:PublishableKey"];
        if (!Uri.TryCreate(supabase, UriKind.Absolute, out var supabaseUri) || supabaseUri.Scheme != "https" ||
            supabaseUri.AbsolutePath != "/" || !string.IsNullOrEmpty(supabaseUri.UserInfo) ||
            !string.IsNullOrEmpty(supabaseUri.Query) || !string.IsNullOrEmpty(supabaseUri.Fragment) ||
            string.IsNullOrWhiteSpace(key) ||
            !Uri.TryCreate(api, UriKind.Absolute, out var apiUri) ||
            !(apiUri.Scheme == "https" || apiUri.Scheme == "http" && apiUri.IsLoopback) ||
            !string.IsNullOrEmpty(apiUri.UserInfo) || !string.IsNullOrEmpty(apiUri.Query) || !string.IsNullOrEmpty(apiUri.Fragment))
            throw new InvalidOperationException("Check desktop appsettings.json: use an HTTPS Supabase URL, its public key, and an HTTPS API URL (HTTP is allowed on localhost).");
        return new(supabaseUri, key, new Uri(apiUri.AbsoluteUri.TrimEnd('/') + "/"));
    }
}
