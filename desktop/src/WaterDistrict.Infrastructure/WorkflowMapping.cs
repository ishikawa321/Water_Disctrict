using Microsoft.EntityFrameworkCore;
using WaterDistrict.Domain;

namespace WaterDistrict.Infrastructure;

public sealed partial class WaterDistrictDbContext
{
    public DbSet<ServiceAccount> Accounts => Set<ServiceAccount>();
    public DbSet<ServiceConcern> Concerns => Set<ServiceConcern>();
    public DbSet<RepairTicket> Tickets => Set<RepairTicket>();
    public DbSet<TicketStatusHistory> History => Set<TicketStatusHistory>();

    private static void ConfigureWorkflows(ModelBuilder model)
    {
        model.Entity<ServiceAccount>(entity =>
        {
            entity.ToTable("service_accounts", "public", table => table.ExcludeFromMigrations());
            entity.HasKey(row => row.Id);
            entity.Property(row => row.Id).HasColumnName("id");
            entity.Property(row => row.AccountNumber).HasColumnName("account_number");
            entity.Property(row => row.HolderName).HasColumnName("holder_name");
            entity.Property(row => row.ServiceAddress).HasColumnName("service_address");
            entity.Property(row => row.Active).HasColumnName("active");
        });
        model.Entity<ServiceConcern>(entity =>
        {
            entity.ToTable("service_concerns", "public", table => table.ExcludeFromMigrations());
            entity.HasKey(row => row.Id);
            entity.Property(row => row.Id).HasColumnName("id").ValueGeneratedNever();
            entity.Property(row => row.AccountId).HasColumnName("account_id");
            entity.Property(row => row.SubmittedBy).HasColumnName("submitted_by");
            entity.Property(row => row.Category).HasColumnName("category");
            entity.Property(row => row.Subject).HasColumnName("subject");
            entity.Property(row => row.Description).HasColumnName("description");
            entity.Property(row => row.Status).HasColumnName("status");
            entity.Property(row => row.AdminResponse).HasColumnName("admin_response");
            entity.Property(row => row.ReviewedBy).HasColumnName("reviewed_by");
            entity.Property(row => row.ReviewedAt).HasColumnName("reviewed_at");
            entity.Property(row => row.CreatedAt).HasColumnName("created_at").HasDefaultValueSql("now()");
            entity.Property(row => row.RepairDispatchedAt).HasColumnName("repair_dispatched_at");
            entity.Property(row => row.Version).IsRowVersion().HasColumnName("xmin");
            entity.HasOne(row => row.Account).WithMany().HasForeignKey(row => row.AccountId).OnDelete(DeleteBehavior.Restrict);
        });
        model.Entity<RepairTicket>(entity =>
        {
            entity.ToTable("repair_tickets", "public", table => table.ExcludeFromMigrations());
            entity.HasKey(row => row.Id);
            entity.Property(row => row.Id).HasColumnName("id").ValueGeneratedNever();
            entity.Property(row => row.ConcernId).HasColumnName("concern_id");
            entity.Property(row => row.CreatedBy).HasColumnName("created_by");
            entity.Property(row => row.UpdatedBy).HasColumnName("updated_by");
            entity.Property(row => row.AssignedTo).HasColumnName("assigned_to");
            entity.Property(row => row.AssignedToUserId).HasColumnName("assigned_to_user_id");
            entity.Property(row => row.Status).HasColumnName("status");
            entity.Property(row => row.LatestUpdate).HasColumnName("latest_update");
            entity.Property(row => row.UpdatedAt).HasColumnName("updated_at").HasDefaultValueSql("now()").ValueGeneratedOnAddOrUpdate();
            entity.Property(row => row.Version).IsRowVersion().HasColumnName("xmin");
            entity.HasOne(row => row.Concern).WithOne().HasForeignKey<RepairTicket>(row => row.ConcernId).OnDelete(DeleteBehavior.Restrict);
        });
        model.Entity<TicketStatusHistory>(entity =>
        {
            entity.ToTable("ticket_status_history", "public");
            entity.HasKey(row => row.Id);
            entity.Property(row => row.Id).HasColumnName("id").UseIdentityByDefaultColumn();
            entity.Property(row => row.TicketId).HasColumnName("ticket_id");
            entity.Property(row => row.ChangedBy).HasColumnName("changed_by");
            entity.Property(row => row.Status).HasColumnName("status");
            entity.Property(row => row.Note).HasColumnName("note");
            entity.Property(row => row.AssignedToUserId).HasColumnName("assigned_to_user_id");
            entity.Property(row => row.AssignedTo).HasColumnName("assigned_to");
            entity.Property(row => row.ChangedAt).HasColumnName("changed_at").HasDefaultValueSql("now()");
            entity.HasOne(row => row.Ticket).WithMany().HasForeignKey(row => row.TicketId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne<AppProfile>().WithMany().HasForeignKey(row => row.ChangedBy).OnDelete(DeleteBehavior.Restrict);
            entity.HasIndex(row => new { row.TicketId, row.Id });
        });
    }
}
