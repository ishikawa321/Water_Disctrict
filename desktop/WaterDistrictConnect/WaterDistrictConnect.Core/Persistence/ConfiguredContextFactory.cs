using Microsoft.EntityFrameworkCore;

namespace WaterDistrictConnect.Core.Persistence;

// Defer validation until an operation runs, so the login UI can report configuration problems.
public sealed class ConfiguredContextFactory(AppConfiguration configuration) : IDbContextFactory<WaterDbContext>
{
    public WaterDbContext CreateDbContext()
    {
        configuration.Validate();
        return new(new DbContextOptionsBuilder<WaterDbContext>()
            .UseNpgsql(configuration.ConnectionString, n => n.CommandTimeout(15)).Options);
    }
}
