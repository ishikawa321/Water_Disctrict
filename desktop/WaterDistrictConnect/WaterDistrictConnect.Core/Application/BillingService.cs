using Microsoft.EntityFrameworkCore;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.Core.Domain;

namespace WaterDistrictConnect.Core.Application;

public record BillRow(Guid Id, Guid AccountId, string Account, DateOnly Month, DateOnly DueDate, decimal Amount, DateTimeOffset? PaidAt, Guid Version)
{
    public string MonthLabel => Month.ToString("MMMM yyyy");
    public string DueLabel => DueDate.ToString("dd MMM yyyy");
    public string AmountLabel => $"PHP {Amount:N2}";
    public string Status => StatusOn(DateOnly.FromDateTime(DateTimeOffset.UtcNow.ToOffset(TimeSpan.FromHours(8)).DateTime));
    public string StatusOn(DateOnly today) => PaidAt.HasValue ? "Paid" : DueDate < today ? "Overdue" : DueDate == today ? "Due today" : "Unpaid";
    public string PaymentLabel => PaidAt.HasValue ? "Paid: " + TimeDisplay.Format(PaidAt.Value) : "Awaiting payment";
}

public sealed partial class WaterService
{
    public static bool CanManageBilling(Identity who) => who.Roles?.Contains("Administrator") == true;

    public async Task<BillRow[]> BillsAsync()
    {
        await using var db = await factory.CreateDbContextAsync();
        var who = await Access.CurrentAsync(db, session);
        if (!CanManageBilling(who) && !who.IsClient) throw new BusinessException("Billing is available to administrators and clients.");
        var bills = await db.Bills.AsNoTracking().Include(x => x.CustomerAccount)
            .Where(x => CanReadBill(who) || (who.IsClient && x.CustomerAccountId == who.AccountId))
            .OrderByDescending(x => x.Month).ThenBy(x => x.CustomerAccount.Number).ToArrayAsync();
        return bills.Select(x => new BillRow(x.Id, x.CustomerAccountId, x.CustomerAccount.ToString(), x.Month, x.DueDate, x.Amount, x.PaidAt, x.Version)).ToArray();
    }
    private static bool CanReadBill(Identity who) => CanManageBilling(who);

    public async Task SaveBillAsync(Guid? id, Guid? version, Guid accountId, DateOnly month, DateOnly dueDate, decimal amount, bool paid)
    {
        await using var db = await factory.CreateDbContextAsync();
        var who = await Access.CurrentAsync(db, session);
        if (!CanManageBilling(who)) throw new BusinessException("Only administrators can change billing.");
        month = new DateOnly(month.Year, month.Month, 1);
        if (amount <= 0 || amount > 999999999.99m || decimal.Round(amount, 2) != amount) throw new BusinessException("Enter a positive amount with at most two decimal places.");
        if (dueDate < month) throw new BusinessException("The due date cannot precede the billing month.");
        if (!await db.Accounts.AnyAsync(x => x.Id == accountId)) throw new BusinessException("Choose a valid customer account.");
        if (await db.Bills.AnyAsync(x => x.CustomerAccountId == accountId && x.Month == month && x.Id != id)) throw new BusinessException("This account already has a bill for that month. Edit the existing bill.");
        var bill = id.HasValue ? await db.Bills.SingleOrDefaultAsync(x => x.Id == id) ?? throw new BusinessException("Bill unavailable.") : new Bill();
        if (id.HasValue && bill.Version != version) throw new BusinessException("This bill changed. Refresh and select it again before saving.");
        bill.CustomerAccountId = accountId; bill.Month = month; bill.DueDate = dueDate; bill.Amount = amount;
        bill.PaidAt = paid ? bill.PaidAt ?? DateTimeOffset.UtcNow : null; bill.Version = Guid.NewGuid();
        if (!id.HasValue) db.Bills.Add(bill);
        Audit(db, who, bill.Id, paid ? "Bill saved as paid" : "Bill saved as unpaid");
        await db.SaveChangesAsync();
    }
}
