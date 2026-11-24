using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using WaterDistrict.Application;
using WaterDistrict.Domain;
namespace WaterDistrict.Api;

public sealed class DependencyExceptionHandler : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception exception, CancellationToken token)
    {
        var problem = exception switch
        {
            WorkflowException failure => new ProblemDetails { Status=failure.StatusCode, Title="Operation not completed", Detail=failure.Message,
                Extensions = { ["code"] = failure.Code } },
            DependencyUnavailableException => new ProblemDetails { Status=503,Title="Required service unavailable",Detail=exception.Message },
            NpgsqlException or DbUpdateException => new ProblemDetails { Status=503,Title="Database operation unavailable",
                Detail="The saved result could not be confirmed. Check connectivity and database setup, then refresh before retrying." },
            _ => null
        };
        if(problem is null) return false;
        http.Response.StatusCode=problem.Status!.Value;
        await http.Response.WriteAsJsonAsync(problem,token);
        return true;
    }
}
