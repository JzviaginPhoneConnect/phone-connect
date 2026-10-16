// PhoneConnect.exe — the Windows launcher.
// It carries the app icon and starts PhoneConnect.sh (the same script as on macOS)
// with the zsh that ships in shell\, without showing a console window. Any
// arguments are passed on to the script (and from there to scrcpy).
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
        string script = Path.Combine(dir, "PhoneConnect.sh");
        string zsh = Path.Combine(dir, @"shell\usr\bin\zsh.exe");
        foreach (string needed in new[] { script, zsh })
        {
            if (!File.Exists(needed))
            {
                MessageBox.Show(Path.GetFileName(needed) + " is missing from the PhoneConnect folder. Please reinstall PhoneConnect.",
                                "PhoneConnect", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        // -f: don't read zsh startup files. The script is given by its name and
        // found in the working directory, so zsh sees it under its own (/c/...) path.
        var cmd = new StringBuilder("-f PhoneConnect.sh");
        foreach (string a in args) cmd.Append(' ').Append(Quote(a));

        var psi = new ProcessStartInfo(zsh, cmd.ToString());
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;     // no console window
        psi.WorkingDirectory = dir;
        psi.EnvironmentVariables["LANG"] = "C.UTF-8";            // text is UTF-8 throughout
        psi.EnvironmentVariables["MSYS2_ARG_CONV_EXCL"] = "*";   // pass arguments to Windows programs as given
        try
        {
            Process.Start(psi);
        }
        catch (Exception e)
        {
            MessageBox.Show("Could not start PhoneConnect: " + e.Message, "PhoneConnect",
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }
}
