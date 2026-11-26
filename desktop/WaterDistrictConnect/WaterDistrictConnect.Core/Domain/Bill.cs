namespace WaterDistrictConnect.Core.Domain;

public class Bill
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CustomerAccountId { get; set; }
    public CustomerAccount CustomerAccount { get; set; } = null!;
    public DateOnly Month { get; set; }
    public DateOnly DueDate { get; set; }
    public decimal Amount { get; set; }
    public DateTimeOffset? PaidAt { get; set; }
    public Guid Version { get; set; } = Guid.NewGuid();
}
