using WaterDistrict.Application;
namespace WaterDistrict.Api;

public static class OfficeEndpoints
{
    private static SessionProfile Actor(HttpContext context)=>(SessionProfile)context.Items[DesktopAuthorizationHandler.SessionItem]!;
    private static string Bearer(HttpContext context)=>context.Request.Headers.Authorization.ToString()[7..].Trim();
    public static void MapOffice(this WebApplication app)
    {
        var group=app.MapGroup("/api/office").RequireAuthorization("Admin");
        group.MapGet("/summary",(HttpContext h,IOfficeService s,CancellationToken t)=>s.SummaryAsync(Actor(h),Bearer(h),t));
        group.MapGet("/accounts",(HttpContext h,IOfficeService s,CancellationToken t)=>s.AccountsAsync(Actor(h),Bearer(h),t));
        group.MapPost("/accounts",(HttpContext h,IOfficeService s,AddOfficeAccount input,CancellationToken t)=>s.AddAccountAsync(Actor(h),Bearer(h),input,t));
        group.MapGet("/bills",(HttpContext h,IOfficeService s,CancellationToken t)=>s.BillsAsync(Actor(h),Bearer(h),t));
        group.MapPost("/bills",(HttpContext h,IOfficeService s,AddOfficeBill input,CancellationToken t)=>s.AddBillAsync(Actor(h),Bearer(h),input,t));
        group.MapGet("/payments",(HttpContext h,IOfficeService s,CancellationToken t)=>s.PaymentsAsync(Actor(h),Bearer(h),t));
        group.MapPost("/payments",(HttpContext h,IOfficeService s,AddOfficePayment input,CancellationToken t)=>s.AddPaymentAsync(Actor(h),Bearer(h),input,t));
        group.MapGet("/announcements",(HttpContext h,IOfficeService s,CancellationToken t)=>s.AnnouncementsAsync(Actor(h),Bearer(h),t));
        group.MapPost("/announcements",(HttpContext h,IOfficeService s,SaveOfficeAnnouncement input,CancellationToken t)=>s.SaveAnnouncementAsync(Actor(h),Bearer(h),null,input,t));
        group.MapPut("/announcements/{id:guid}",(HttpContext h,IOfficeService s,Guid id,SaveOfficeAnnouncement input,CancellationToken t)=>s.SaveAnnouncementAsync(Actor(h),Bearer(h),id,input,t));
    }
}
