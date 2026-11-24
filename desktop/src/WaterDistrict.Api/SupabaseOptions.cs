namespace WaterDistrict.Api;

public sealed class SupabaseOptions
{
    public string Url { get; set; } = "";
    public string PublishableKey { get; set; } = "";
    public string Issuer => Url.TrimEnd('/') + "/auth/v1";

    public void Validate()
    {
        if (!Uri.TryCreate(Url, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
            uri.AbsolutePath != "/" || !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.UserInfo) ||
            string.IsNullOrWhiteSpace(PublishableKey))
            throw new InvalidOperationException("Configure a valid HTTPS Supabase URL and public publishable key on the API.");
    }
}
