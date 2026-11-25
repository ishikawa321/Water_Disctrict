using System.Reflection;
namespace WaterDistrict.Infrastructure;
public static class EmbeddedSql
{
    public static string Read(string name)
    {
        using var stream = typeof(EmbeddedSql).Assembly.GetManifestResourceStream("WaterDistrict.Infrastructure.Sql." + name)
            ?? throw new InvalidOperationException("Missing database migration resource: " + name);
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
