using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using WaterDistrictConnect.Core.Domain;

namespace WaterDistrictConnect.Core.Persistence;
public class WaterDbContext(DbContextOptions<WaterDbContext> options) : DbContext(options)
{
    public DbSet<Bill> Bills => Set<Bill>();
    public DbSet<User> Users => Set<User>(); public DbSet<Role> Roles => Set<Role>(); public DbSet<CustomerAccount> Accounts => Set<CustomerAccount>();
    public DbSet<AccountOwnership> Ownerships => Set<AccountOwnership>(); public DbSet<ServiceConcern> Concerns => Set<ServiceConcern>();
    public DbSet<ConcernEvent> ConcernEvents => Set<ConcernEvent>(); public DbSet<RepairTicket> Tickets => Set<RepairTicket>();
    public DbSet<TicketEvent> TicketEvents => Set<TicketEvent>(); public DbSet<PlumberResource> Plumbers => Set<PlumberResource>(); public DbSet<AuditRecord> Audits => Set<AuditRecord>();
    protected override void OnModelCreating(ModelBuilder m)
    {
        m.Entity<Bill>().HasIndex(x => new { x.CustomerAccountId, x.Month }).IsUnique();
        m.Entity<Bill>().Property(x => x.Amount).HasPrecision(11, 2);
        m.Entity<Bill>().Property(x => x.Version).IsConcurrencyToken();
        m.Entity<Bill>().ToTable(t => {
            t.HasCheckConstraint("CK_Bill_Amount", "\"Amount\" > 0");
            t.HasCheckConstraint("CK_Bill_Dates", "EXTRACT(DAY FROM \"Month\") = 1 AND \"DueDate\" >= \"Month\"");
        });
        m.HasSequence<long>("concern_reference_seq").StartsAt(100001);
        m.Entity<ServiceConcern>().Property(x => x.Reference).HasDefaultValueSql("'MWD-' || nextval('concern_reference_seq')::text");
        m.Entity<ServiceConcern>().HasIndex(x => x.SubmissionKey).IsUnique();
        m.Entity<ServiceConcern>().Property(x => x.IntakeChannel).HasConversion<string>().HasMaxLength(40);
        m.Entity<UserRole>().HasKey(x => new { x.UserId, x.RoleId }); m.Entity<RolePermission>().HasKey(x => new { x.RoleId, x.Permission });
        m.Entity<AccountOwnership>().HasKey(x => new { x.UserId, x.CustomerAccountId });
        m.Entity<AccountOwnership>().HasIndex(x => x.UserId).IsUnique(); // One fictional account per client in this mini-system.
        m.Entity<User>().HasIndex(x => x.Username).IsUnique(); m.Entity<Role>().HasIndex(x => x.Name).IsUnique(); m.Entity<CustomerAccount>().HasIndex(x => x.Number).IsUnique();
        m.Entity<PlumberResource>().HasIndex(x => x.Name).IsUnique();
        m.Entity<ServiceConcern>().HasIndex(x => x.Reference).IsUnique(); m.Entity<RepairTicket>().HasIndex(x => x.Reference).IsUnique();
        m.Entity<ServiceConcern>().HasIndex(x => new { x.CustomerAccountId, x.SubmittedAt }); m.Entity<ServiceConcern>().HasIndex(x => new { x.State, x.Category });
        m.Entity<RepairTicket>().HasOne(x => x.ServiceConcern).WithOne(x => x.Ticket).HasForeignKey<RepairTicket>(x => x.ServiceConcernId);
        m.Entity<RepairTicket>().HasIndex(x => x.ServiceConcernId).IsUnique();
        m.Entity<ServiceConcern>().Property(x => x.Version).IsConcurrencyToken(); m.Entity<RepairTicket>().Property(x => x.Version).IsConcurrencyToken();
        m.Entity<ConcernEvent>().HasIndex(x => new { x.ServiceConcernId, x.At }); m.Entity<TicketEvent>().HasIndex(x => new { x.RepairTicketId, x.At });
        foreach (var e in m.Model.GetEntityTypes())
        {
            foreach (var p in e.GetProperties().Where(p => p.ClrType == typeof(string))) { p.SetMaxLength(200); p.IsNullable = false; }
            foreach (var fk in e.GetForeignKeys()) fk.DeleteBehavior = DeleteBehavior.Restrict;
        }
        m.Entity<ServiceConcern>().Property(x => x.LegacyIntakeChannel).IsRequired(false);
        m.Entity<ServiceConcern>().Property(x => x.IntakeChannel).HasMaxLength(40);
        m.Entity<User>().Property(x => x.Username).HasMaxLength(64); m.Entity<User>().Property(x => x.PasswordHash).HasMaxLength(500);
        m.Entity<ServiceConcern>().Property(x => x.Subject).HasMaxLength(160); m.Entity<ServiceConcern>().Property(x => x.Description).HasMaxLength(4000);
        m.Entity<ServiceConcern>().Property(x => x.Location).HasMaxLength(300); m.Entity<CustomerAccount>().Property(x => x.Address).HasMaxLength(300);
        m.Entity<ConcernEvent>().Property(x => x.Text).HasMaxLength(4000); m.Entity<TicketEvent>().Property(x => x.Text).HasMaxLength(2000);
        m.Entity<RepairTicket>().Property(x => x.CompletionSummary).HasMaxLength(2000); m.Entity<RepairTicket>().Property(x => x.SignedJobOrder).HasMaxLength(160);
        m.Entity<ServiceConcern>().ToTable(t => { t.HasCheckConstraint("CK_Concern_Category", "\"Category\" BETWEEN 0 AND 4"); t.HasCheckConstraint("CK_Concern_State", "\"State\" BETWEEN 0 AND 4"); t.HasCheckConstraint("CK_Concern_Channel", "\"IntakeChannel\" IN ('DesktopClient','Telephone','WalkIn','Other')"); t.HasCheckConstraint("CK_Concern_Content", "length(trim(\"Subject\")) > 0 AND length(trim(\"Description\")) > 0 AND length(trim(\"Location\")) > 0"); });
        m.Entity<RepairTicket>().ToTable(t => { t.HasCheckConstraint("CK_Ticket_State", "\"State\" BETWEEN 0 AND 4"); t.HasCheckConstraint("CK_Ticket_Assignment", "\"State\" NOT IN (1,2,3,4) OR \"PlumberResourceId\" IS NOT NULL"); t.HasCheckConstraint("CK_Ticket_Completion", "\"State\" NOT IN (3,4) OR (length(trim(\"CompletionSummary\")) > 0 AND \"ResolvedAt\" IS NOT NULL)"); t.HasCheckConstraint("CK_Ticket_Closure", "\"State\" <> 4 OR (length(trim(\"SignedJobOrder\")) > 0 AND \"ClosedAt\" IS NOT NULL)"); });
    }
}
public sealed class DesignFactory : IDesignTimeDbContextFactory<WaterDbContext>
{
    public WaterDbContext CreateDbContext(string[] args) => new(new DbContextOptionsBuilder<WaterDbContext>().UseNpgsql(Environment.GetEnvironmentVariable("MWD_CONNECTION") ?? "Host=localhost;Database=mwd;Username=CONFIGURE_ME").Options);
}
