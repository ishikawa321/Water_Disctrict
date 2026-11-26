using Npgsql;
namespace WaterDistrict.Tests;

[Collection("Postgres")]
public sealed class ClientRegistrationTests
{
    private static CancellationToken Token => TestContext.Current.CancellationToken;
    private static async Task Prepare(PostgresDatabase db)
    {
        await db.SqlAsync("""
            ALTER TABLE auth.users ADD COLUMN email text,
              ADD COLUMN email_confirmed_at timestamptz,
              ADD COLUMN raw_user_meta_data jsonb DEFAULT '{}';
            INSERT INTO public.service_accounts(account_number,holder_name,service_address)
              VALUES ('MWD-001249','Existing holder','Existing address');
            """);
        await db.SqlAsync(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"enable_client_registration.sql"),Token));
        await db.SqlAsync(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"require_client_approval.sql"),Token));
    }
    private static async Task<object?> Scalar(PostgresDatabase db, string sql)
    {
        await using var connection = new NpgsqlConnection(db.Connection);
        await connection.OpenAsync(Token);
        return await new NpgsqlCommand(sql,connection).ExecuteScalarAsync(Token);
    }
    private static Task Insert(PostgresDatabase db,Guid id,string address="Client service address") => db.SqlAsync($$"""
        INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES
          ('{{id}}','{{id}}@example.test',jsonb_build_object(
            'registration_source','client_signup_v1','display_name','Registered client',
            'service_address','{{address}}','role','admin','account_number','MWD-000001'));
        """);
    private static Task Confirm(PostgresDatabase db,Guid id) => db.SqlAsync($"UPDATE auth.users SET email_confirmed_at=now() WHERE id='{id}'");

    private static Task Approve(PostgresDatabase db,Guid id,Guid? actor=null) => db.SqlAsync($"SET request.jwt.claim.sub='{actor??db.Admin.UserId}'; SELECT * FROM public.approve_client_registration('{id}')");
    [Fact]
    public async Task Confirmed_signup_atomically_creates_a_client_and_owned_sequential_account()
    {
        await using var db=await PostgresDatabase.CreateAsync(verifiedSchema:true);await Prepare(db);
        var id=Guid.NewGuid();await Insert(db,id);
        Assert.Equal(false,await Scalar(db,$"SELECT active FROM public.profiles WHERE user_id='{id}'"));
        await Confirm(db,id);
        Assert.Equal(false,await Scalar(db,$"SELECT active FROM public.profiles WHERE user_id='{id}'"));
        Assert.Equal(0L,await Scalar(db,$"SELECT count(*) FROM public.account_access WHERE user_id='{id}'"));
        await Assert.ThrowsAsync<PostgresException>(()=>Approve(db,id,id));
        await Assert.ThrowsAsync<PostgresException>(()=>Approve(db,id,db.Staff.UserId));
        await Approve(db,id);
        Assert.Equal(true,await Scalar(db,$"SELECT active FROM public.profiles WHERE user_id='{id}'"));
        Assert.Equal("client",await Scalar(db,$"SELECT role FROM public.profiles WHERE user_id='{id}'"));
        Assert.Equal("MWD-001250",await Scalar(db,$"SELECT s.account_number FROM public.service_accounts s JOIN public.account_access a ON a.account_id=s.id WHERE a.user_id='{id}'"));
        Assert.Equal(db.Admin.UserId,await Scalar(db,$"SELECT verified_by FROM public.account_access WHERE user_id='{id}'"));
        Assert.Equal("REGISTRATION-APPROVAL:"+id,await Scalar(db,$"SELECT authorization_reference FROM public.account_access WHERE user_id='{id}'"));
        await Confirm(db,id);await Approve(db,id);
        Assert.Equal(1L,await Scalar(db,$"SELECT count(*) FROM public.account_access WHERE user_id='{id}'"));
        Assert.Equal("MWD-001249",await Scalar(db,"SELECT account_number FROM public.service_accounts WHERE holder_name='Existing holder'"));
        // The normal desktop repository sees the exact row created by registration.
        await using var context=db.Open();
        Assert.Contains(context.Accounts, row=>row.AccountNumber=="MWD-001250" && row.HolderName=="Registered client");
    }

    [Fact]
    public async Task Simultaneous_approvals_allocate_unique_consecutive_numbers()
    {
        await using var db=await PostgresDatabase.CreateAsync(verifiedSchema:true);await Prepare(db);
        var ids=Enumerable.Range(0,12).Select(_=>Guid.NewGuid()).ToArray();
        foreach(var id in ids)await Insert(db,id);
        await Task.WhenAll(ids.Select(id=>Approve(db,id)));
        Assert.Equal(13L,await Scalar(db,"SELECT count(DISTINCT account_number) FROM public.service_accounts WHERE account_number LIKE 'MWD-%'"));
        Assert.Equal(1261L,await Scalar(db,"SELECT last_value FROM public.client_account_number_counter"));
        Assert.Equal(12L,await Scalar(db,"SELECT count(*) FROM public.account_access WHERE authorization_reference LIKE 'REGISTRATION-APPROVAL:%'"));
    }

    [Fact]
    public async Task Invalid_signup_rolls_back_confirmation_profile_account_and_counter()
    {
        await using var db=await PostgresDatabase.CreateAsync(verifiedSchema:true);await Prepare(db);
        var id=Guid.NewGuid();
        await Assert.ThrowsAsync<PostgresException>(()=>Insert(db,id,""));
        Assert.Equal(0L,await Scalar(db,$"SELECT count(*) FROM auth.users WHERE id='{id}'"));
        Assert.Equal(1249L,await Scalar(db,"SELECT last_value FROM public.client_account_number_counter"));
        await Insert(db,id);await Approve(db,id);
        Assert.Equal(1250L,await Scalar(db,"SELECT last_value FROM public.client_account_number_counter"));
    }

    [Fact]
    public async Task Existing_roles_and_links_are_preserved_and_counter_is_not_publicly_writable()
    {
        await using var db=await PostgresDatabase.CreateAsync(verifiedSchema:true);await Prepare(db);
        foreach(var id in new[]{db.Admin.UserId,db.ClientId})
        {
            await db.SqlAsync($$"""UPDATE auth.users SET raw_user_meta_data='{"registration_source":"client_signup_v1","role":"admin"}' WHERE id='{{id}}'""");
            await Confirm(db,id);
        }
        Assert.Equal("admin",await Scalar(db,$"SELECT role FROM public.profiles WHERE user_id='{db.Admin.UserId}'"));
        Assert.Equal(db.AccountId,await Scalar(db,$"SELECT account_id FROM public.account_access WHERE user_id='{db.ClientId}'"));
        Assert.Equal(false,await Scalar(db,"SELECT has_table_privilege('authenticated','public.client_account_number_counter','UPDATE')"));
        Assert.Equal(false,await Scalar(db,"SELECT has_function_privilege('anon','public.provision_registered_client()','EXECUTE')"));
        Assert.Equal(false,await Scalar(db,"SELECT has_table_privilege('authenticated','public.service_accounts','INSERT')"));
        // Rerunning the migration neither resets the counter nor changes existing accounts.
        await db.SqlAsync(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"enable_client_registration.sql"),Token));
        await db.SqlAsync(await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory,"require_client_approval.sql"),Token));
        Assert.Equal(1249L,await Scalar(db,"SELECT last_value FROM public.client_account_number_counter"));
    }

    [Fact]
    public async Task Duplicate_approvals_are_idempotent_and_pending_rows_are_private()
    {
        await using var db=await PostgresDatabase.CreateAsync(verifiedSchema:true);await Prepare(db);
        var id=Guid.NewGuid();var other=Guid.NewGuid();await Insert(db,id);await Insert(db,other);
        Assert.Equal(1L,await Scalar(db,$"SET ROLE authenticated; SET request.jwt.claim.sub='{id}'; SELECT count(*) FROM public.client_registrations"));
        Assert.Equal(0L,await Scalar(db,$"SET ROLE authenticated; SET request.jwt.claim.sub='{id}'; SELECT count(*) FROM public.profiles"));
        Assert.Equal(0L,await Scalar(db,$"SET ROLE authenticated; SET request.jwt.claim.sub='{id}'; SELECT count(*) FROM public.service_accounts"));
        Assert.Equal(2L,await Scalar(db,$"SET ROLE authenticated; SET request.jwt.claim.sub='{db.Admin.UserId}'; SELECT count(*) FROM public.client_registrations"));
        Assert.Equal(false,await Scalar(db,"SELECT has_table_privilege('authenticated','public.client_registrations','UPDATE')"));
        await Task.WhenAll(Enumerable.Range(0,5).Select(_=>Approve(db,id)));
        Assert.Equal(1L,await Scalar(db,$"SELECT count(*) FROM public.account_access WHERE user_id='{id}'"));
        Assert.Equal(1250L,await Scalar(db,"SELECT last_value FROM public.client_account_number_counter"));
        Assert.Equal("Pending",await Scalar(db,$"SELECT status FROM public.client_registrations WHERE user_id='{other}'"));
        await Confirm(db,id);
        Assert.Equal("Approved",await Scalar(db,$"SELECT status FROM public.client_registrations WHERE user_id='{id}'"));
    }

    [Fact]
    public async Task Numbers_expand_beyond_six_digits_without_truncation()
    {
        await using var db=await PostgresDatabase.CreateAsync(verifiedSchema:true);await Prepare(db);
        await db.SqlAsync("INSERT INTO public.service_accounts(account_number,holder_name,service_address) VALUES ('MWD-999999','Existing','Existing')");
        var id=Guid.NewGuid();await Insert(db,id);await Confirm(db,id);await Approve(db,id);
        Assert.Equal("MWD-1000000",await Scalar(db,$"SELECT s.account_number FROM public.service_accounts s JOIN public.account_access a ON a.account_id=s.id WHERE a.user_id='{id}'"));
    }
}
