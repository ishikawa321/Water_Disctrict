using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.EntityFrameworkCore;
using WaterDistrictConnect.Core.Domain;

namespace WaterDistrictConnect.ViewModels;
public abstract partial class ViewModelBase : ObservableObject
{
    [ObservableProperty] private bool isBusy;
    partial void OnIsBusyChanged(bool value) { OnPropertyChanged("Empty"); OnPropertyChanged(nameof(HasFeedback)); }
    [ObservableProperty] private string error = "";
    [ObservableProperty] private string success = "";
    public bool HasFeedback => IsBusy || !string.IsNullOrEmpty(Error) || !string.IsNullOrEmpty(Success);
    partial void OnErrorChanged(string value) { OnPropertyChanged(nameof(HasFeedback)); OnPropertyChanged("Empty"); }
    partial void OnSuccessChanged(string value) => OnPropertyChanged(nameof(HasFeedback));
    public async Task RunAsync(Func<Task> work)
    {
        if (IsBusy) return;
        IsBusy = true; Error = ""; Success = "";
        try { await work(); }
        catch (BusinessException e) { Error = e.Message; }
        catch (DbUpdateConcurrencyException) { Error = "Another office user changed this record. Refresh and review the latest details before trying again."; }
        catch (DbUpdateException) { Error = "The change could not be saved. A record may have changed or conflict with this action. Refresh the details and retry; your input is retained."; }
        catch (Exception e) when (e is Npgsql.NpgsqlException or TimeoutException or System.Net.Sockets.SocketException) { Error = "Cannot reach PostgreSQL. Check the database connection and availability, then retry. Your entered information is retained."; }
        catch (Exception) { Error = "This operation could not finish. Check configuration and database migrations, then retry. Your entered information is retained."; }
        finally { IsBusy = false; }
    }
}
public interface IConfirmationService { Task<bool> ConfirmAsync(string title, string message); }
