// PhoneConnect.exe — the Windows launcher.
// It carries the app icon and starts PhoneConnect.sh (the same script as on macOS)
// with the zsh that ships in shell\, without showing a console window. Any
// arguments are passed on to the script (and from there to scrcpy).
//
// PhoneConnect.exe --status <status file> <pid> is the status window instead: it
// shows, in plain words, what PhoneConnect is doing until the phone's picture appears
// (started by platform\status_window.sh; the macOS version is macos/StatusWindow.swift).
//
// Built by build/build-windows.ps1 with the C# compiler that ships with Windows
// (.NET Framework), so it's written in plain C# 5.

using System;
using System.Diagnostics;
using System.Drawing;
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
        if (args.Length >= 3 && args[0] == "--status")
        {
            int pid;
            if (!int.TryParse(args[2], out pid)) return 2;
            Application.EnableVisualStyles();
            Application.Run(new StatusWindow(args[1], pid));
            return 0;
        }

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

// The status window. PhoneConnect.sh appends one line per step to the status file; the
// newest is shown large with a moving bar, the few before it small. Closes when a line
// "__done__" appears or the PhoneConnect process (pid) is gone. Cancel stops PhoneConnect.
sealed class StatusWindow : Form
{
    readonly string statusPath;
    readonly int mainPid;
    readonly Label current = new Label();
    readonly Label earlier = new Label();
    readonly Timer timer = new Timer();
    int shownLines = -1;
    bool closingQuietly;

    public StatusWindow(string statusPath, int mainPid)
    {
        this.statusPath = statusPath;
        this.mainPid = mainPid;

        Text = "PhoneConnect";
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        Font = new Font("Segoe UI", 10f);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        StartPosition = FormStartPosition.Manual;

        var picture = new PictureBox();
        picture.Size = new Size(48, 48);
        picture.SizeMode = PictureBoxSizeMode.Zoom;
        picture.Margin = new Padding(0, 0, 16, 0);
        picture.Image = AppIcon(48).ToBitmap();

        current.Text = "Starting...";
        current.Font = new Font("Segoe UI Semibold", 12f);
        current.AutoSize = true;
        current.MaximumSize = new Size(360, 0);
        current.Margin = new Padding(0, 0, 0, 6);

        var bar = new ProgressBar();
        bar.Style = ProgressBarStyle.Marquee;
        bar.MarqueeAnimationSpeed = 30;
        bar.Size = new Size(360, 6);
        bar.Margin = new Padding(0, 0, 0, 8);

        earlier.AutoSize = true;
        earlier.MaximumSize = new Size(360, 0);
        earlier.ForeColor = SystemColors.GrayText;
        earlier.Font = new Font("Segoe UI", 9f);

        var text = new FlowLayoutPanel();
        text.FlowDirection = FlowDirection.TopDown;
        text.WrapContents = false;
        text.AutoSize = true;
        text.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        text.Controls.Add(current);
        text.Controls.Add(bar);
        text.Controls.Add(earlier);

        var cancel = new Button();
        cancel.Text = "Cancel";
        cancel.AutoSize = true;
        cancel.MinimumSize = new Size(100, 30);
        cancel.Anchor = AnchorStyles.Right;
        cancel.Margin = new Padding(0, 12, 0, 0);
        cancel.Click += delegate { CancelPhoneConnect(); };
        CancelButton = cancel;

        var layout = new TableLayoutPanel();
        layout.ColumnCount = 2;
        layout.RowCount = 2;
        layout.AutoSize = true;
        layout.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        layout.Padding = new Padding(16);
        layout.Controls.Add(picture, 0, 0);
        layout.Controls.Add(text, 1, 0);
        layout.Controls.Add(cancel, 1, 1);
        Controls.Add(layout);

        timer.Interval = 250;
        timer.Tick += delegate { Poll(); };

        Load += delegate
        {
            // low on the screen, so PhoneConnect's own dialogs (in the middle) stay clear of it
            Rectangle area = Screen.PrimaryScreen.WorkingArea;
            Location = new Point(area.Left + (area.Width - Width) / 2,
                                 area.Bottom - Height - area.Height * 18 / 100);
            Poll();
            timer.Start();
        };
        Shown += delegate
        {
            // come to the front once, without staying on top of everything
            TopMost = true;
            TopMost = false;
            Activate();
        };
        FormClosing += delegate(object sender, FormClosingEventArgs e)
        {
            // closing it with the X means the same as Cancel
            if (!closingQuietly && e.CloseReason == CloseReason.UserClosing) StopPhoneConnect();
        };
    }

    static Icon AppIcon(int size)
    {
        string ico = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "PhoneConnect.ico");
        try { if (File.Exists(ico)) return new Icon(ico, size, size); } catch (Exception) { }
        return Icon.ExtractAssociatedIcon(Application.ExecutablePath);
    }

    bool MainAlive()
    {
        try { return !Process.GetProcessById(mainPid).HasExited; }
        catch (ArgumentException) { return false; }      // no such process
        catch (Exception) { return true; }                // can't tell: keep showing
    }

    void Poll()
    {
        if (!MainAlive()) { CloseQuietly(); return; }
        string[] lines;
        try
        {
            using (var fs = new FileStream(statusPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var reader = new StreamReader(fs, new UTF8Encoding(false)))
                lines = reader.ReadToEnd().Replace("\r", "").Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
        }
        catch (IOException) { return; }
        catch (UnauthorizedAccessException) { return; }
        if (Array.IndexOf(lines, "__done__") >= 0) { CloseQuietly(); return; }
        if (lines.Length == 0 || lines.Length == shownLines) return;
        shownLines = lines.Length;
        current.Text = lines[lines.Length - 1];
        var sb = new StringBuilder();
        for (int i = Math.Max(0, lines.Length - 6); i < lines.Length - 1; i++)
        {
            if (sb.Length > 0) sb.Append('\n');
            sb.Append(lines[i]);
        }
        earlier.Text = sb.ToString();
    }

    void CloseQuietly()
    {
        closingQuietly = true;
        timer.Stop();
        Close();
    }

    void CancelPhoneConnect()
    {
        StopPhoneConnect();
        CloseQuietly();
    }

    // Stop PhoneConnect's script and everything it started (its zsh, adb calls, scrcpy)
    void StopPhoneConnect()
    {
        try
        {
            var psi = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "taskkill.exe"),
                                           "/T /F /PID " + mainPid);
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            Process.Start(psi).WaitForExit(5000);
        }
        catch (Exception) { }
    }
}
