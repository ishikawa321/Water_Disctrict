using System.Runtime.InteropServices;

namespace WaterDistrictConnect.Presentation;

internal static class UiMotion
{
    // Read only: follows Windows Settings > Accessibility > Visual effects > Animation effects.
    public static bool Enabled
    {
        get
        {
            if (string.Equals(Environment.GetEnvironmentVariable("MWD_REDUCED_MOTION"), "true", StringComparison.OrdinalIgnoreCase)) return false;
            return !OperatingSystem.IsWindows() || (SystemParametersInfo(0x1042, 0, out var enabled, 0) && enabled);
        }
    }

    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SystemParametersInfo(uint action, uint parameter, [MarshalAs(UnmanagedType.Bool)] out bool value, uint flags);
}
