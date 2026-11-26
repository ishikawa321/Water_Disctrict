using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using WaterDistrict.Application;
using WaterDistrict.Domain;

namespace WaterDistrict.Api;

// Uses the same Data API contract and caller RLS as the mobile draft.
// Repair processing remains on the EF Core transaction path.
public sealed class SupabaseOfficeService(HttpClient http,TimeProvider? clock=null):IOfficeService
{
    private readonly TimeProvider time=clock??TimeProvider.System;
    private const string AccountFields="id,account_number,holder_name,service_address,active";
    private const string BillFields="id,bill_number,billing_period_start,billing_period_end,due_date,amount_due,service_accounts(account_number),offline_payments(amount_paid)";
    private const string PaymentFields="receipt_reference,payment_date,amount_paid,verified_at,bills(bill_number,service_accounts(account_number))";
    private const string NoticeFields="id,title,message,published,updated_at";
    private static void Admin(SessionProfile actor)
    { if(actor.Role!="admin")throw new WorkflowException("forbidden","Only active administrators can use this office operation.",403); }
    public async Task<OfficeSummary> SummaryAsync(SessionProfile actor,string bearer,CancellationToken token)
    {
        Admin(actor);
        var pending=await Count("service_concerns?status=in.(Submitted,Under%20review)",bearer,token);
        var repairs=await Count("repair_tickets?status=in.(Open,Assigned,In%20progress)",bearer,token);
        return new(pending,repairs);
    }
    public async Task<IReadOnlyList<OfficeAccount>> AccountsAsync(SessionProfile actor,string bearer,CancellationToken token)
    { Admin(actor);return (await Rows(HttpMethod.Get,$"service_accounts?select={AccountFields}&order=account_number&limit=1000",bearer,null,token)).Select(row=>Decode(()=>Account(row))).ToArray(); }
    public async Task<OfficeAccount> AddAccountAsync(SessionProfile actor,string bearer,AddOfficeAccount input,CancellationToken token)
    {
        Admin(actor);
        var values=new {account_number=WorkflowRules.Required(input.AccountNumber,"Account number",80),holder_name=WorkflowRules.Required(input.HolderName,"Holder name",200),
            service_address=WorkflowRules.Required(input.ServiceAddress,"Service address",500),active=true,updated_by=actor.UserId};
        return Account(One(await Rows(HttpMethod.Post,$"service_accounts?select={AccountFields}",bearer,values,token)));
    }
    public async Task<IReadOnlyList<OfficeBill>> BillsAsync(SessionProfile actor,string bearer,CancellationToken token)
    { Admin(actor);return (await Rows(HttpMethod.Get,$"bills?select={BillFields}&order=due_date.desc&limit=1000",bearer,null,token)).Select(row=>Decode(()=>Bill(row))).ToArray(); }
    public async Task<OfficeBill> AddBillAsync(SessionProfile actor,string bearer,AddOfficeBill input,CancellationToken token)
    {
        Admin(actor);if(input.AccountId==Guid.Empty)throw new WorkflowException("account","Select a service account.");
        Date(input.PeriodStart);Date(input.PeriodEnd);Date(input.DueDate);Money(input.AmountDue);
        if(input.PeriodEnd<input.PeriodStart)throw new WorkflowException("dates","The period end cannot precede the period start.");
        var values=new {account_id=input.AccountId,bill_number=WorkflowRules.Required(input.BillNumber,"Bill number",100),billing_period_start=input.PeriodStart,
            billing_period_end=input.PeriodEnd,due_date=input.DueDate,amount_due=input.AmountDue,created_by=actor.UserId};
        return Bill(One(await Rows(HttpMethod.Post,$"bills?select={BillFields}",bearer,values,token)));
    }
    public async Task<IReadOnlyList<OfficePayment>> PaymentsAsync(SessionProfile actor,string bearer,CancellationToken token)
    { Admin(actor);return (await Rows(HttpMethod.Get,$"offline_payments?select={PaymentFields}&order=payment_date.desc&limit=1000",bearer,null,token)).Select(row=>Decode(()=>Payment(row))).ToArray(); }
    public async Task<IReadOnlyList<OfficePayment>> PaymentsForBillAsync(SessionProfile actor,string bearer,Guid billId,CancellationToken token)
    {
        Admin(actor);
        if(billId==Guid.Empty)throw new WorkflowException("bill","Select a valid bill.");
        return (await Rows(HttpMethod.Get,$"offline_payments?select={PaymentFields}&bill_id=eq.{billId:D}&order=payment_date.desc&limit=1000",bearer,null,token)).Select(row=>Decode(()=>Payment(row))).ToArray();
    }
    public async Task<OfficePayment> AddPaymentAsync(SessionProfile actor,string bearer,AddOfficePayment input,CancellationToken token)
    {
        Admin(actor);Money(input.AmountPaid);Date(input.PaymentDate);
        if(input.BillId==Guid.Empty)throw new WorkflowException("bill","Select a bill.");
        if(!input.Verified)throw new WorkflowException("verification","Confirm the offline payment has been verified before recording it.");
        if(input.PaymentDate>DateOnly.FromDateTime(time.GetLocalNow().DateTime))throw new WorkflowException("date","The payment date cannot be in the future.");
        var values=new {bill_id=input.BillId,receipt_reference=WorkflowRules.Required(input.ReceiptReference,"Receipt/reference",150),payment_date=input.PaymentDate,
            amount_paid=input.AmountPaid,verified_by=actor.UserId};
        return Payment(One(await Rows(HttpMethod.Post,$"offline_payments?select={PaymentFields}",bearer,values,token)));
    }
    public async Task<IReadOnlyList<OfficeAnnouncement>> AnnouncementsAsync(SessionProfile actor,string bearer,CancellationToken token)
    { Admin(actor);return (await Rows(HttpMethod.Get,$"announcements?select={NoticeFields}&order=updated_at.desc&limit=1000",bearer,null,token)).Select(row=>Decode(()=>Notice(row))).ToArray(); }
    public async Task<OfficeAnnouncement> SaveAnnouncementAsync(SessionProfile actor,string bearer,Guid? id,SaveOfficeAnnouncement input,CancellationToken token)
    {
        Admin(actor);
        var title=WorkflowRules.Required(input.Title,"Title",150);
        if(title.StartsWith(OfficeAnnouncement.InterruptionPrefix,StringComparison.Ordinal))title=title[OfficeAnnouncement.InterruptionPrefix.Length..].Trim();
        title=WorkflowRules.Required(title,"Title",150);
        var storedTitle=WorkflowRules.Required((input.IsInterruption?OfficeAnnouncement.InterruptionPrefix:"")+title,"Full announcement title (including interruption marker)",150);
        var values=new Dictionary<string,object?> { ["title"]=storedTitle,
            ["message"]=WorkflowRules.Required(input.Message,"Announcement message",5000),["published"]=input.Published,["updated_by"]=actor.UserId };
        if(id is null)values["created_by"]=actor.UserId;else values["updated_at"]=time.GetUtcNow();
        var path=$"announcements?select={NoticeFields}"+(id is null?"":$"&id=eq.{id:D}");
        return Notice(One(await Rows(id is null?HttpMethod.Post:HttpMethod.Patch,path,bearer,values,token)));
    }
    private static void Money(decimal value)
    { if(value<=0 || decimal.Round(value,2)!=value || value>9999999999.99m)throw new WorkflowException("amount","Enter a positive amount with at most two decimal places."); }
    private static void Date(DateOnly value)
    { if(value.Year<2000 || value.Year>2100)throw new WorkflowException("date","Select a valid date between 2000 and 2100."); }
    private HttpRequestMessage Request(HttpMethod method,string path,string bearer,object? input)
    {
        var request=new HttpRequestMessage(method,path);request.Headers.Authorization=new AuthenticationHeaderValue("Bearer",bearer);
        if(input is not null){request.Content=JsonContent.Create(input);request.Headers.TryAddWithoutValidation("Prefer","return=representation");}
        return request;
    }
    private async Task<int> Count(string path,string bearer,CancellationToken token)
    {
        try
        {
            using var request=Request(HttpMethod.Head,path,bearer,null);request.Headers.TryAddWithoutValidation("Prefer","count=exact");
            using var response=await http.SendAsync(request,token);await Check(response,token);
            var count=response.Content.Headers.ContentRange?.Length;
            if(count is null || count>int.MaxValue)throw new DependencyUnavailableException("The overview service did not return valid counts.");
            return (int)count;
        }
        catch(HttpRequestException){throw new DependencyUnavailableException("The office data service could not be reached.");}
        catch(OperationCanceledException) when(!token.IsCancellationRequested){throw new DependencyUnavailableException("The office data service timed out.");}
    }
    private async Task<JsonElement[]> Rows(HttpMethod method,string path,string bearer,object? input,CancellationToken token)
    {
        try
        {
            using var request=Request(method,path,bearer,input);using var response=await http.SendAsync(request,token);await Check(response,token);
            using var document=JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
            if(document.RootElement.ValueKind!=JsonValueKind.Array)throw new JsonException();
            return document.RootElement.EnumerateArray().Select(row=>row.Clone()).ToArray();
        }
        catch(HttpRequestException){throw new DependencyUnavailableException(input is null?"The office data service could not be reached.":"The saved result could not be confirmed. Refresh the list before retrying.");}
        catch(OperationCanceledException) when(!token.IsCancellationRequested){throw new DependencyUnavailableException("The office data service timed out. Refresh before retrying a save.");}
        catch(Exception exception) when(exception is JsonException or FormatException or InvalidOperationException or KeyNotFoundException)
        {throw new DependencyUnavailableException("The office data service returned incomplete information. Refresh before retrying.");}
    }
    private static Task Check(HttpResponseMessage response,CancellationToken token)
    {
        if(response.IsSuccessStatusCode)return Task.CompletedTask;
        throw response.StatusCode switch {
            HttpStatusCode.Forbidden or HttpStatusCode.Unauthorized=>new WorkflowException("forbidden","Office operation denied. Check the active Admin profile and database policies.",403),
            HttpStatusCode.Conflict=>new WorkflowException("duplicate","That account, bill or receipt/reference already exists. Refresh before retrying.",409),
            HttpStatusCode.BadRequest or HttpStatusCode.UnprocessableEntity=>new WorkflowException("validation","The database rejected these values. Check the selected record, dates and amount.",422),
            _=>new DependencyUnavailableException("The office data service is unavailable. Refresh before retrying a save.") };
    }
    private static T Decode<T>(Func<T> read)
    {
        try{return read();}
        catch(Exception exception) when(exception is JsonException or FormatException or InvalidOperationException or KeyNotFoundException or OverflowException)
        {throw new DependencyUnavailableException("The office data service returned invalid record fields. Refresh before retrying.");}
    }
    private static JsonElement One(JsonElement[] rows)=>rows.Length==1?rows[0]:throw new DependencyUnavailableException("No single saved record was confirmed. Refresh before retrying.");
    private static string Text(JsonElement row,string field)=>row.GetProperty(field).GetString()??throw new JsonException();
    private static decimal Decimal(JsonElement row,string field)=>decimal.Parse(row.GetProperty(field).ToString(),NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture);
    private static OfficeAccount Account(JsonElement row)=>Decode(()=>new OfficeAccount(Guid.Parse(Text(row,"id")),Text(row,"account_number"),Text(row,"holder_name"),Text(row,"service_address"),row.GetProperty("active").GetBoolean()));
    private static string NestedText(JsonElement row,string relation,string field)=>row.TryGetProperty(relation,out var parent)&&parent.ValueKind==JsonValueKind.Object?Text(parent,field):"Unavailable";
    private static OfficeBill Bill(JsonElement row)=>Decode(()=>new OfficeBill(Guid.Parse(Text(row,"id")),Text(row,"bill_number"),NestedText(row,"service_accounts","account_number"),DateOnly.Parse(Text(row,"billing_period_start"),CultureInfo.InvariantCulture),
        DateOnly.Parse(Text(row,"billing_period_end"),CultureInfo.InvariantCulture),DateOnly.Parse(Text(row,"due_date"),CultureInfo.InvariantCulture),Decimal(row,"amount_due"),
        row.GetProperty("offline_payments").EnumerateArray().Sum(payment=>Decimal(payment,"amount_paid"))));
    private static OfficePayment Payment(JsonElement row)=>Decode(()=>new OfficePayment(Text(row,"receipt_reference"),NestedText(row,"bills","bill_number"),row.GetProperty("bills").ValueKind==JsonValueKind.Object?NestedText(row.GetProperty("bills"),"service_accounts","account_number"):"Unavailable",
        DateOnly.Parse(Text(row,"payment_date"),CultureInfo.InvariantCulture),Decimal(row,"amount_paid"),row.GetProperty("verified_at").ValueKind==JsonValueKind.Null?null:DateTimeOffset.Parse(Text(row,"verified_at"),CultureInfo.InvariantCulture)));
    private static OfficeAnnouncement Notice(JsonElement row)=>Decode(()=>new OfficeAnnouncement(Guid.Parse(Text(row,"id")),Text(row,"title"),Text(row,"message"),row.GetProperty("published").GetBoolean(),DateTimeOffset.Parse(Text(row,"updated_at"),CultureInfo.InvariantCulture)));
}
