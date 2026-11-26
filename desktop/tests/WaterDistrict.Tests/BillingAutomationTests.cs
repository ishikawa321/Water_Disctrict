using System.Text.Json;
using Npgsql;

namespace WaterDistrict.Tests;

[Collection("Postgres")]
public sealed class BillingAutomationTests
{
    private static CancellationToken Token => TestContext.Current.CancellationToken;
    private static Task<JsonElement> As(PostgresDatabase db, Guid user, string sql) => WebOfficeWorkflowTests.AsCaller(db, user, sql);
    private static async Task Install(PostgresDatabase db)
    {
        var sql = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "billing-automation.sql"), Token);
        await db.SqlAsync(sql); await db.SqlAsync(sql);
    }
    private static async Task<JsonElement> Read(PostgresDatabase db, string sql)
    { await using var c = new NpgsqlConnection(db.Connection); await c.OpenAsync(Token); await using var cmd = new NpgsqlCommand(sql, c); return JsonDocument.Parse((string)(await cmd.ExecuteScalarAsync(Token))!).RootElement.Clone(); }

    [Fact]
    public async Task Payment_confirmation_is_admin_only_idempotent_ten_digits_and_rejects_overpayment()
    {
        await using var db = await PostgresDatabase.CreateAsync(verifiedSchema: true); await Install(db);
        var request = Guid.NewGuid();
        var bill = await As(db, db.Admin.UserId, $"select public.wd_billing_create_bill('{request}','{db.AccountId}',100,(clock_timestamp() at time zone 'Asia/Manila')::date+3)::text");
        var billId = bill.GetProperty("id").GetGuid(); Assert.StartsWith("MWD-", bill.GetProperty("bill_number").GetString());
        Assert.Equal(billId, (await As(db, db.Admin.UserId, $"select public.wd_billing_create_bill('{request}','{db.AccountId}',100,(clock_timestamp() at time zone 'Asia/Manila')::date+3)::text")).GetProperty("id").GetGuid());
        var paymentRequest = Guid.NewGuid(); var call = $"select public.wd_billing_confirm_payment('{paymentRequest}','{billId}',40,(clock_timestamp() at time zone 'Asia/Manila')::date)::text";
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Staff.UserId, call))).SqlState);
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.ClientId, call))).SqlState);
        var payment = await As(db, db.Admin.UserId, call); Assert.Matches("^[0-9]{10}$", payment.GetProperty("receipt_reference").GetString()!);
        Assert.Equal(payment.GetProperty("id").GetGuid(), (await As(db, db.Admin.UserId, call)).GetProperty("id").GetGuid());
        Assert.Equal("40001", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Admin.UserId, call.Replace(",40,", ",41,")))).SqlState);
        Assert.Equal("22023", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Admin.UserId, $"select public.wd_billing_confirm_payment('{Guid.NewGuid()}','{billId}',61,current_date)::text"))).SqlState);
        // Direct legacy mobile inserts also get an automatic reference and use Manila date.
        var direct = await As(db, db.Admin.UserId, $"with p as(insert into public.offline_payments(bill_id,amount_paid,payment_date,verified_by) values('{billId}',60,(clock_timestamp() at time zone 'Asia/Manila')::date,'{db.Admin.UserId}') returning receipt_reference) select to_jsonb(p)::text from p");
        Assert.Matches("^[0-9]{10}$", direct.GetProperty("receipt_reference").GetString()!); Assert.NotEqual(payment.GetProperty("receipt_reference").GetString(), direct.GetProperty("receipt_reference").GetString());
        var totals = await Read(db, $"select jsonb_build_object('count',count(*),'paid',sum(amount_paid))::text from public.offline_payments where bill_id='{billId}'"); Assert.Equal(2, totals.GetProperty("count").GetInt32()); Assert.Equal(100, totals.GetProperty("paid").GetDecimal());
        var hidden = await As(db, db.OtherClientId, $"select jsonb_build_object('count',count(*))::text from public.bills where id='{billId}'"); Assert.Equal(0, hidden.GetProperty("count").GetInt32());
    }

    [Fact]
    public async Task Monthly_jobs_catch_up_once_per_account_roll_due_dates_and_reject_public_scheduler_access()
    {
        await using var db = await PostgresDatabase.CreateAsync(verifiedSchema: true); await Install(db);
        await db.SqlAsync("create or replace function wd_billing_private.today() returns date language sql as $$ select date '2031-01-01' $$");
        await As(db, db.Admin.UserId, $"select public.wd_billing_set_plan('{db.AccountId}',250,true)::text");
        await As(db, db.Admin.UserId, $"select public.wd_billing_set_plan('{db.OtherAccountId}',400,false)::text");
        await db.SqlAsync("update public.billing_plans set next_issue_date='2031-01-28'");
        await db.SqlAsync("select wd_billing_private.run('2031-02-28');select wd_billing_private.run('2031-02-28');");
        var bills = await Read(db, "select jsonb_agg(jsonb_build_object('number',bill_number,'cycle',automatic_cycle,'due',due_date) order by automatic_cycle)::text from public.bills");
        Assert.Equal(2, bills.GetArrayLength()); Assert.Equal("2031-01-31", bills[0].GetProperty("due").GetString()); Assert.Equal("2031-03-03", bills[1].GetProperty("due").GetString()); Assert.NotEqual(bills[0].GetProperty("number").GetString(), bills[1].GetProperty("number").GetString());
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Admin.UserId, "select public.wd_billing_run_daily()::text"))).SqlState);
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Staff.UserId, $"select public.wd_billing_set_plan('{db.AccountId}',250,true)::text"))).SqlState);
        var status = await As(db, db.Admin.UserId, "select public.wd_billing_status()::text"); Assert.False(status.GetProperty("scheduleActive").GetBoolean());
        await db.SqlAsync("create or replace function wd_billing_private.today() returns date language sql as $$ select date '2032-02-28' $$");
        await As(db, db.Admin.UserId, $"select public.wd_billing_set_plan('{db.OtherAccountId}',400,true)::text");
        var leap = await Read(db, $"select jsonb_build_object('due',due_date)::text from public.bills where account_id='{db.OtherAccountId}'"); Assert.Equal("2032-03-02", leap.GetProperty("due").GetString());
    }

    [Fact]
    public async Task Concurrent_full_payments_cannot_pay_twice_or_create_duplicate_references()
    {
        await using var db = await PostgresDatabase.CreateAsync(verifiedSchema: true); await Install(db);
        var b = await As(db, db.Admin.UserId, $"select public.wd_billing_create_bill('{Guid.NewGuid()}','{db.AccountId}',100,current_date+3)::text"); var id = b.GetProperty("id").GetGuid();
        async Task<bool> Confirm() { try { await As(db, db.Admin.UserId, $"select public.wd_billing_confirm_payment('{Guid.NewGuid()}','{id}',100,current_date)::text"); return true; } catch (PostgresException e) { Assert.Equal("22023", e.SqlState); return false; } }
        Assert.Single(await Task.WhenAll(Confirm(), Confirm()), r => r);
        var result = await Read(db, $"select jsonb_build_object('paid',sum(amount_paid),'count',count(*))::text from public.offline_payments where bill_id='{id}'"); Assert.Equal(100, result.GetProperty("paid").GetDecimal()); Assert.Equal(1, result.GetProperty("count").GetInt32());
    }

    [Fact]
    public async Task Existing_unpaid_bills_get_simple_daily_interest_and_full_payment_stops_it_for_all_clients()
    {
        await using var db = await PostgresDatabase.CreateAsync(verifiedSchema: true); var open = Guid.NewGuid(); var paid = Guid.NewGuid();
        await db.SqlAsync($"insert into public.bills(id,account_id,bill_number,billing_period_start,billing_period_end,due_date,amount_due,created_by) values('{open}','{db.AccountId}','LEGACY-OPEN',current_date-30,current_date-3,(clock_timestamp() at time zone 'Asia/Manila')::date-2,500,'{db.Admin.UserId}'),('{paid}','{db.AccountId}','LEGACY-PAID',current_date-30,current_date-3,current_date-10,100,'{db.Admin.UserId}');insert into public.offline_payments(bill_id,receipt_reference,payment_date,amount_paid,verified_by) values('{paid}','OLD-RECEIPT',current_date-5,100,'{db.Admin.UserId}');");
        await Install(db);
        var first = await As(db, db.ClientId, $"select to_jsonb(b)::text from public.bills b where id='{open}'"); Assert.Equal(500, first.GetProperty("base_amount_due").GetDecimal()); Assert.Equal(10, first.GetProperty("interest_amount").GetDecimal()); Assert.Equal(510, first.GetProperty("amount_due").GetDecimal());
        await db.SqlAsync($"select wd_billing_private.accrue('{open}',wd_billing_private.today()+1);select wd_billing_private.accrue('{open}',wd_billing_private.today()+1)");
        var next = await Read(db, $"select to_jsonb(b)::text from public.bills b where id='{open}'"); Assert.Equal(515, next.GetProperty("amount_due").GetDecimal());
        await As(db, db.Admin.UserId, $"select public.wd_billing_confirm_payment('{Guid.NewGuid()}','{open}',515,current_date)::text");
        await db.SqlAsync($"select wd_billing_private.accrue('{open}',wd_billing_private.today()+100)");
        var final = await As(db, db.ClientId, $"select to_jsonb(b)::text from public.bills b where id='{open}'"); Assert.Equal(515, final.GetProperty("amount_due").GetDecimal()); Assert.Equal(3, final.GetProperty("interest_days").GetInt32());
        var oldPaid = await Read(db, $"select to_jsonb(b)::text from public.bills b where id='{paid}'"); Assert.Equal(100, oldPaid.GetProperty("amount_due").GetDecimal()); Assert.Equal(0, oldPaid.GetProperty("interest_days").GetInt32());
    }
}
