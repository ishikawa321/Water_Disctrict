using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using WaterDistrictConnect.Core.Persistence;
using WaterDistrictConnect.Core.Application;
using WaterDistrictConnect.Core.Authentication;
using WaterDistrictConnect.ViewModels;
namespace WaterDistrictConnect;
public static class Composition
{
    public static ServiceProvider Create()
    {
        var services = new ServiceCollection();
        var config = AppConfiguration.Load();
        services.AddSingleton(config);
        services.AddSingleton<IDbContextFactory<WaterDbContext>, ConfiguredContextFactory>();
        services.AddSingleton<Session>(); services.AddTransient<AuthenticationService>(); services.AddTransient<WaterService>(); services.AddTransient<DatabaseSetup>(); services.AddSingleton<IConfirmationService, ConfirmationService>(); services.AddTransient<RootViewModel>();
        return services.BuildServiceProvider();
    }
}

