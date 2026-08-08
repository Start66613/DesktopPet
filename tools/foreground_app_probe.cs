using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

internal static class ForegroundAppProbe
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    private static readonly HashSet<string> IgnoredProcesses = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "system", "system idle process", "registry", "smss", "csrss", "wininit", "winlogon",
        "services", "lsass", "svchost", "fontdrvhost", "dwm", "conhost", "sihost", "taskhostw",
        "runtimebroker", "searchhost", "shellexperiencehost", "textinputhost", "applicationframehost",
        "startmenuexperiencehost", "explorer", "securityhealthservice", "msmpeng", "nvcontainer",
        "nvdisplay.container", "nvidia overlay", "asusoptimizationstartuptask", "ipf_helper",
        "armourycrate.usersessionhelper"
    };

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    private static string ProcessName(uint processId)
    {
        try
        {
            using (var process = Process.GetProcessById((int)processId))
            {
                return process.ProcessName ?? string.Empty;
            }
        }
        catch
        {
            return string.Empty;
        }
    }

    private static bool IsIgnoredProcess(string processName)
    {
        if (string.IsNullOrEmpty(processName))
            return true;
        return IgnoredProcesses.Contains(processName)
            || processName.StartsWith("Godot_v", StringComparison.OrdinalIgnoreCase)
            || processName.Equals("Godot", StringComparison.OrdinalIgnoreCase)
            || processName.Equals("DesktopPet", StringComparison.OrdinalIgnoreCase);
    }

    public static void Main()
    {
        var foreground = string.Empty;
        uint foregroundPid;
        GetWindowThreadProcessId(GetForegroundWindow(), out foregroundPid);
        foreground = ProcessName(foregroundPid);
        if (IsIgnoredProcess(foreground))
            foreground = string.Empty;

        var visible = new List<string>();
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
        {
            if (!IsWindowVisible(hWnd) || GetWindowTextLength(hWnd) <= 0)
                return true;

            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);
            var processName = ProcessName(processId);
            if (!IsIgnoredProcess(processName) && !visible.Contains(processName))
                visible.Add(processName);
            return visible.Count < 8;
        }, IntPtr.Zero);

        Console.WriteLine("FOREGROUND:" + foreground);
        Console.WriteLine("VISIBLE:" + string.Join(",", visible.ToArray()));
    }
}
