using System.Text.Json;
using Npgsql;

namespace WaterDistrict.Tests;

[Collection("Postgres")]
public sealed class BillingReleaseDateTests
{
    private static CancellationToken Token => TestContext.Current.CancellationToken;
    private static Task<JsonElement> As(PostgresDatabase db, Guid user, string sql) => WebOfficeWorkflowTests.AsCaller(db, user, sql);
    private static async Task Install(PostgresDatabase db)
    {
        await db.SqlAsync("alter table auth.users add column if not exists email text,add column if not exists email_confirmed_at timestamptz,add column if not exists raw_user_meta_data jsonb default '{}'");
        await WebOfficeWorkflowTests.Install(db);
        await db.SqlAsync(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "billing-automation.sql"), Token));
        await db.SqlAsync(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "staff-role.sql"), Token));
        var migration = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "billing-release-dates.sql"), Token);
        await db.SqlAsync(migration); await db.SqlAsync(migration);
    }

    [Fact]
    public async Task Scheduled_bill_is_hidden_until_release_while_today_bill_is_visible_before_due_and_retries_are_safe()
    {
        await using var db = await PostgresDatabase.CreateAsync(verifiedSchema: true); await Install(db);
        var request = Guid.NewGuid();
        var call = $"select public.wd_billing_create_bill('{request}','{db.AccountId}',100,wd_billing_private.today()+6,wd_billing_private.today()+3)::text";
        // Callers cannot access private date helpers; use the same Manila date expression.
        call = call.Replace("wd_billing_private.today()", "(clock_timestamp() at time zone 'Asia/Manila')::date");
        var bill = await As(db, db.Admin.UserId, call); var id = bill.GetProperty("id").GetGuid();
        Assert.Equal(id, (await As(db, db.Admin.UserId, call)).GetProperty("id").GetGuid());
        var count = $"select jsonb_build_object('count',count(*))::text from public.bills where id='{id}'";
        Assert.Equal(0, (await As(db, db.ClientId, count)).GetProperty("count").GetInt32());
        Assert.Equal(1, (await As(db, db.Admin.UserId, count)).GetProperty("count").GetInt32());
        Assert.Equal(1, (await As(db, db.Staff.UserId, count)).GetProperty("count").GetInt32());
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Staff.UserId, call))).SqlState);
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.ClientId, call))).SqlState);
        Assert.Equal("40001", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Admin.UserId, call.Replace("::date+3", "::date+2")))).SqlState);
        Assert.Equal("22023", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Admin.UserId, call.Replace("::date+6", "::date+1")))).SqlState);
        // Model arrival of the chosen date without changing the machine clock.
        await db.SqlAsync($"update public.bills set release_date=(clock_timestamp() at time zone 'Asia/Manila')::date where id='{id}'");
        Assert.Equal(1, (await As(db, db.ClientId, count)).GetProperty("count").GetInt32());
        Assert.Equal(0, (await As(db, db.OtherClientId, count)).GetProperty("count").GetInt32());
        // Old native callers keep their four-argument immediate-release operation.
        var immediate = await As(db, db.Admin.UserId, $"select public.wd_billing_create_bill('{Guid.NewGuid()}','{db.AccountId}',200,(clock_timestamp() at time zone 'Asia/Manila')::date+3)::text");
        Assert.Equal(200, (await As(db, db.ClientId, $"select to_jsonb(b)::text from public.bills b where id='{immediate.GetProperty("id").GetGuid()}'")).GetProperty("amount_due").GetDecimal());
    }

    [Fact]
    public async Task Chosen_monthly_day_replaces_28th_and_short_months_restore_original_day_without_duplicate_cycles()
    {
        await using var db = await PostgresDatabase.CreateAsync(verifiedSchema: true); await Install(db);
        await db.SqlAsync("create or replace function wd_billing_private.today() returns date language sql as $$ select date '2031-01-17' $$");
        var chosen = await As(db, db.Admin.UserId, $"select public.wd_billing_set_plan('{db.AccountId}',250,true,'2031-01-17')::text");
        Assert.Equal("2031-02-17", chosen.GetProperty("next_issue_date").GetString());
        var bills = await As(db, db.Admin.UserId, $"select jsonb_agg(to_jsonb(b) order by automatic_cycle)::text from public.bills b where account_id='{db.AccountId}'");
        Assert.Single(bills.EnumerateArray()); Assert.Equal("2031-01-20", bills[0].GetProperty("due_date").GetString());
        await As(db, db.Admin.UserId, $"select public.wd_billing_set_plan('{db.OtherAccountId}',400,true,'2031-01-31')::text");
        await db.SqlAsync("select wd_billing_private.run('2031-03-31');select wd_billing_private.run('2031-03-31');");
        var monthEnd = await As(db, db.Admin.UserId, $"select jsonb_agg(to_jsonb(b) order by automatic_cycle)::text from public.bills b where account_id='{db.OtherAccountId}'");
        Assert.Equal(3, monthEnd.GetArrayLength());
        Assert.Equal("2031-01-31", monthEnd[0].GetProperty("release_date").GetString());
        Assert.Equal("2031-02-28", monthEnd[1].GetProperty("release_date").GetString());
        Assert.Equal("2031-03-31", monthEnd[2].GetProperty("release_date").GetString());
        Assert.Equal("2031-03-03", monthEnd[1].GetProperty("due_date").GetString());
        Assert.Equal("42501", (await Assert.ThrowsAsync<PostgresException>(() => As(db, db.Staff.UserId, $"select public.wd_billing_set_plan('{db.AccountId}',100,true,'2031-04-10')::text"))).SqlState);
    }
}
