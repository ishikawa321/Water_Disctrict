using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using WaterDistrict.Api;
using WaterDistrict.Application;
using WaterDistrict.Domain;

namespace WaterDistrict.Tests;

public sealed class OfficeServiceTests
{
    private static CancellationToken Token=>TestContext.Current.CancellationToken;
    private static readonly SessionProfile Admin=new(Guid.NewGuid(),"Office Admin","admin",[]);
    private static readonly Guid AccountId=Guid.NewGuid();
    private static readonly Guid BillId=Guid.NewGuid();
    private static object Account()=>new {id=AccountId,account_number="WD-001",holder_name="Example holder",service_address="Example address",active=true};
    private static object Bill()=>new {id=BillId,bill_number="B-001",billing_period_start="2026-10-01",billing_period_end="2026-10-31",due_date="2026-11-15",amount_due="450.00",service_accounts=new {account_number="WD-001"},offline_payments=new[]{new {amount_paid="120.50"}}};
    [Fact]
    public async Task Account_creation_uses_mobile_fields_and_verified_actor_and_returns_saved_record()
    {
        var service=Service(async request=>
        {
            Assert.Equal("caller-token",request.Headers.Authorization!.Parameter);
            Assert.Equal(HttpMethod.Post,request.Method);Assert.Contains("return=representation",request.Headers.GetValues("Prefer"));
            using var payload=JsonDocument.Parse(await request.Content!.ReadAsStringAsync(Token));
            Assert.Equal("WD-001",payload.RootElement.GetProperty("account_number").GetString());
            Assert.Equal(Admin.UserId,payload.RootElement.GetProperty("updated_by").GetGuid());
            Assert.True(payload.RootElement.GetProperty("active").GetBoolean());return Json(new[]{Account()});
        });
        var saved=await service.AddAccountAsync(Admin,"caller-token",new(" WD-001 ","Example holder","Example address"),Token);
        Assert.Equal(AccountId,saved.Id);
    }
    [Theory]
    [InlineData("account")][InlineData("bill")][InlineData("payment")][InlineData("announcement")]
    public async Task Staff_cannot_read_admin_modules_even_if_the_service_is_called_directly(string module)
    {
        var service=Service(_=>throw new InvalidOperationException("Must not contact data API"));var staff=Admin with {Role="staff"};
        var failure=await Assert.ThrowsAsync<WorkflowException>(async()=>
        {
            switch(module){case "account":await service.AccountsAsync(staff,"token",Token);break;case "bill":await service.BillsAsync(staff,"token",Token);break;
                case "payment":await service.PaymentsAsync(staff,"token",Token);break;default:await service.AnnouncementsAsync(staff,"token",Token);break;}
        });Assert.Equal(403,failure.StatusCode);
    }
    [Fact]
    public async Task Bills_read_true_embedded_payments_and_calculate_remaining_using_decimal()
    {
        var service=Service(_=>Task.FromResult(Json(new[]{Bill()})));
        var bill=Assert.Single(await service.BillsAsync(Admin,"token",Token));
        Assert.Equal(450m,bill.AmountDue);Assert.Equal(120.50m,bill.Paid);Assert.Equal(329.50m,bill.Remaining);
    }
    [Fact]
    public async Task Bill_payment_history_filters_before_the_server_list_limit_and_preserves_caller_token()
    {
        var service=Service(request=>
        {
            Assert.Equal("caller-token",request.Headers.Authorization!.Parameter);
            Assert.Contains($"bill_id=eq.{BillId:D}",request.RequestUri!.Query);
            Assert.Contains("limit=1000",request.RequestUri.Query);
            return Task.FromResult(Json(Array.Empty<object>()));
        });
        Assert.Empty(await service.PaymentsForBillAsync(Admin,"caller-token",BillId,Token));
        await Assert.ThrowsAsync<WorkflowException>(()=>service.PaymentsForBillAsync(Admin with {Role="staff"},"caller-token",BillId,Token));
        await Assert.ThrowsAsync<WorkflowException>(()=>service.PaymentsForBillAsync(Admin,"caller-token",Guid.Empty,Token));
    }
    [Fact]
    public async Task Invalid_bill_dates_and_fractional_centavo_amounts_send_no_write()
    {
        var service=Service(_=>throw new InvalidOperationException("No write expected"));
        var input=new AddOfficeBill(AccountId,"B-001",new(2026,10,31),new(2026,10,1),new(2026,11,15),450m);
        await Assert.ThrowsAsync<WorkflowException>(()=>service.AddBillAsync(Admin,"token",input,Token));
        await Assert.ThrowsAsync<WorkflowException>(()=>service.AddBillAsync(Admin,"token",input with {PeriodEnd=new(2026,10,31),AmountDue=1.001m},Token));
    }
    [Fact]
    public async Task Unverified_or_future_payment_is_rejected_without_contacting_database()
    {
        var service=Service(_=>throw new InvalidOperationException("No write expected"));
        var payment=new AddOfficePayment(BillId,"R-001",DateOnly.FromDateTime(DateTime.Today),100m,false);
        await Assert.ThrowsAsync<WorkflowException>(()=>service.AddPaymentAsync(Admin,"token",payment,Token));
        await Assert.ThrowsAsync<WorkflowException>(()=>service.AddPaymentAsync(Admin,"token",payment with {Verified=true,PaymentDate=new(2100,1,1)},Token));
    }
    [Fact]
    public async Task Payment_stamps_verifier_and_waits_for_saved_database_verification_time()
    {
        var service=Service(async request=>
        {
            using var payload=JsonDocument.Parse(await request.Content!.ReadAsStringAsync(Token));
            Assert.Equal(Admin.UserId,payload.RootElement.GetProperty("verified_by").GetGuid());
            Assert.False(payload.RootElement.TryGetProperty("verified_at",out _));
            return Json(new[]{new {receipt_reference="R-001",payment_date="2026-10-20",amount_paid="100.00",verified_at="2026-10-20T01:00:00Z",bills=new {bill_number="B-001",service_accounts=new {account_number="WD-001"}}}});
        });
        var saved=await service.AddPaymentAsync(Admin,"token",new(BillId,"R-001",new(2026,10,20),100m,true),Token);
        Assert.NotNull(saved.VerifiedAt);Assert.Equal("B-001",saved.BillNumber);
    }
    [Fact]
    public async Task Announcement_edit_keeps_the_mobile_interruption_prefix_and_draft_state()
    {
        var id=Guid.NewGuid();
        var service=Service(async request=>
        {
            Assert.Equal(HttpMethod.Patch,request.Method);Assert.Contains(id.ToString(),request.RequestUri!.Query);
            using var payload=JsonDocument.Parse(await request.Content!.ReadAsStringAsync(Token));
            Assert.Equal("[Service interruption] Planned maintenance",payload.RootElement.GetProperty("title").GetString());
            Assert.False(payload.RootElement.GetProperty("published").GetBoolean());Assert.Equal(Admin.UserId,payload.RootElement.GetProperty("updated_by").GetGuid());
            Assert.False(payload.RootElement.TryGetProperty("created_by",out _));
            return Json(new[]{new {id,title="[Service interruption] Planned maintenance",message="Recorded notice.",published=false,updated_at="2026-11-25T00:00:00Z"}});
        });
        var saved=await service.SaveAnnouncementAsync(Admin,"token",id,new("Planned maintenance","Recorded notice.",false,true),Token);
        Assert.Equal("Planned maintenance",saved.DisplayTitle);Assert.True(saved.IsInterruption);Assert.False(saved.Published);
    }
    [Fact]
    public async Task Exact_counts_come_from_database_headers_instead_of_list_length()
    {
        var service=Service(request=>
        {
            Assert.Equal(HttpMethod.Head,request.Method);
            var response=Json(Array.Empty<object>());response.Content.Headers.ContentRange=new ContentRangeHeaderValue(request.RequestUri!.AbsolutePath.EndsWith("service_concerns")?7:3);
            return Task.FromResult(response);
        });
        var summary=await service.SummaryAsync(Admin,"token",Token);Assert.Equal(7,summary.PendingConcerns);Assert.Equal(3,summary.ActiveRepairs);
    }
    [Theory]
    [InlineData(HttpStatusCode.Conflict,409)][InlineData(HttpStatusCode.Forbidden,403)]
    public async Task Failed_database_writes_are_never_reported_as_success(HttpStatusCode status,int expected)
    {
        var service=Service(_=>Task.FromResult(new HttpResponseMessage(status)));
        var failure=await Assert.ThrowsAsync<WorkflowException>(()=>service.AddAccountAsync(Admin,"token",new("WD-001","Holder","Address"),Token));Assert.Equal(expected,failure.StatusCode);
    }
    [Fact]
    public async Task Zero_row_update_and_malformed_money_are_dependency_failures()
    {
        var empty=Service(_=>Task.FromResult(Json(Array.Empty<object>())));
        await Assert.ThrowsAsync<DependencyUnavailableException>(()=>empty.SaveAnnouncementAsync(Admin,"token",Guid.NewGuid(),new("Title","Message",true,false),Token));
        var malformed=Service(_=>Task.FromResult(Json(new[]{new {id=BillId,bill_number="B-001",billing_period_start="2026-10-01",billing_period_end="2026-10-31",due_date="2026-11-15",amount_due="invalid",offline_payments=Array.Empty<object>()}})));
        await Assert.ThrowsAsync<DependencyUnavailableException>(()=>malformed.BillsAsync(Admin,"token",Token));
    }

    [Fact]
    public async Task Interruption_marker_counts_toward_the_live_announcement_title_limit()
    {
        var service=Service(_=>throw new InvalidOperationException("Invalid title must not be sent to the data service."));
        var failure=await Assert.ThrowsAsync<WorkflowException>(()=>service.SaveAnnouncementAsync(Admin,"token",null,new(new string('t',150),"Notice body.",false,true),Token));
        Assert.Equal("validation",failure.Code);Assert.Contains("150",failure.Message);
    }
    private static HttpResponseMessage Json<T>(T value)=>new(HttpStatusCode.OK){Content=JsonContent.Create(value)};
    private static SupabaseOfficeService Service(Func<HttpRequestMessage,Task<HttpResponseMessage>> send)=>new(new HttpClient(new Handler(send)){BaseAddress=new("https://test.supabase.co/rest/v1/")});
    private sealed class Handler(Func<HttpRequestMessage,Task<HttpResponseMessage>> send):HttpMessageHandler
    {protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)=>send(request);}
}
