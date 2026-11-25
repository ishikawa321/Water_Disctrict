using Microsoft.EntityFrameworkCore;
using WaterDistrict.Domain;

namespace WaterDistrict.Infrastructure;

public sealed partial class WaterDistrictDbContext(DbContextOptions<WaterDistrictDbContext> options) : DbContext(options)
{
    public DbSet<AppProfile> Profiles => Set<AppProfile>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        ConfigureWorkflows(modelBuilder);
        // Existing Supabase table. Confirm catalog types before extending this mapping.
        // EF must never create/drop the shared identity table from this provisional model.
        modelBuilder.Entity<AppProfile>(entity =>
        {
            entity.ToTable("profiles", "public", table => table.ExcludeFromMigrations());
            entity.HasKey(profile => profile.UserId);
            entity.Property(profile => profile.UserId).HasColumnName("user_id");
            entity.Property(profile => profile.DisplayName).HasColumnName("display_name");
            entity.Property(profile => profile.Role).HasColumnName("role");
            entity.Property(profile => profile.Active).HasColumnName("active");
        });
    }
}
