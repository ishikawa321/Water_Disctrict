using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace WaterDistrict.Infrastructure;

public sealed class DatabaseContextFactory : IDesignTimeDbContextFactory<WaterDistrictDbContext>
{
    public WaterDistrictDbContext CreateDbContext(string[] args)
    {
        var connection = Environment.GetEnvironmentVariable("ConnectionStrings__WaterDistrict");
        if (string.IsNullOrWhiteSpace(connection))
            throw new InvalidOperationException("Set ConnectionStrings__WaterDistrict locally before running EF tools.");
        return new WaterDistrictDbContext(new DbContextOptionsBuilder<WaterDistrictDbContext>()
            .UseNpgsql(connection).Options);
    }
}
