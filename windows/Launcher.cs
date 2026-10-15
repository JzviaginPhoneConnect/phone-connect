// PhoneConnect.exe — the Windows launcher.
// It carries the app icon and starts PhoneConnect.ps1 with PowerShell, without
// showing a console window. Any arguments are passed on to the script (and from
// there to scrcpy).
//
// Built by build/build-windows.ps1 with the C# compiler that ships with Windows
// (.NET Framework), so it's written in plain C# 5.

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("PhoneConnect")]
[assembly: AssemblyProduct("PhoneConnect")]
[assembly: AssemblyDescription("Mirror and control your Android phone")]

static class Launcher
{
    static string Quote(string a)
    {
        if (a.Length > 0 && a.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) return a;
        var sb = new StringBuilder("\"");
        int backslashes = 0;
        foreach (char c in a)
        {
            if (c == '\\') { backslashes++; continue; }
            if (c == '"') sb.Append('\\', backslashes * 2 + 1);
            else sb.Append('\\', backslashes);
            backslashes = 0;
            sb.Append(c);
        }
        sb.Append('\\', backslashes * 2);
        return sb.Append('"').ToString();
    }

    [STAThread]
    static int Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "PhoneConnect.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("PhoneConnect.ps1 is missing next to PhoneConnect.exe. Please reinstall PhoneConnect.",
                            "PhoneConnect", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        var cmd = new StringBuilder();
        cmd.Append("-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File ");
        cmd.Append(Quote(script));
        foreach (string a in args) cmd.Append(' ').Append(Quote(a));

        string powershell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
        if (!File.Exists(powershell)) powershell = "powershell.exe";

        var psi = new ProcessStartInfo(powershell, cmd.ToString());
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;     // no console window
        psi.WorkingDirectory = dir;
        try
        {
            Process.Start(psi);
        }
        catch (Exception e)
        {
            MessageBox.Show("Could not start PowerShell: " + e.Message, "PhoneConnect",
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }
}
