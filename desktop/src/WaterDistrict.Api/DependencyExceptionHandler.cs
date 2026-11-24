using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using WaterDistrict.Application;

namespace WaterDistrict.Api;

public sealed class DependencyExceptionHandler : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        if (exception is not DependencyUnavailableException) return false;
        httpContext.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
        await httpContext.Response.WriteAsJsonAsync(new ProblemDetails {
            Status = 503, Title = "Required service unavailable", Detail = exception.Message
        }, cancellationToken);
        return true;
    }
}
