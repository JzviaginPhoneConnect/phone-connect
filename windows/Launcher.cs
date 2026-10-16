// PhoneConnect.exe — the Windows launcher.
// It carries the app icon and starts PhoneConnect.sh (the same script as on macOS)
// with the zsh that ships in shell\, without showing a console window. Any
// arguments are passed on to the script (and from there to scrcpy).
//
// PhoneConnect.exe --status <status file> is the status window instead: it
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
        if (args.Length >= 2 && args[0] == "--status")
        {
            Application.EnableVisualStyles();
            Application.Run(new StatusWindow(args[1]));
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
// newest is shown large with a moving bar, the few before it small. It only reads and
// writes files (no process handling, which antivirus scanners distrust):
//   <status file>         a line "__done__" closes the window
//   <status file>.alive   PhoneConnect.sh refreshes it; when it goes stale, it's gone
//   <status file>.cancel  Cancel creates it; PhoneConnect.sh then stops itself
sealed class StatusWindow : Form
{
    readonly string statusPath;
    readonly DateTime started = DateTime.UtcNow;
    readonly Label current = new Label();
    readonly Label earlier = new Label();
    readonly Timer timer = new Timer();
    int shownLines = -1;
    bool closingQuietly;

    public StatusWindow(string statusPath)
    {
        this.statusPath = statusPath;

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
        picture.Image = AppImage(128);

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
            if (!closingQuietly && e.CloseReason == CloseReason.UserClosing) AskToStop();
        };
    }

    // The app picture for the window, from PhoneConnect.ico: the smallest image at least
    // `size` pixels wide. Its images are stored as PNG, which Icon.ToBitmap() turns into
    // noise on .NET Framework, so the PNG is read directly.
    static Image AppImage(int size)
    {
        try
        {
            byte[] ico = File.ReadAllBytes(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "PhoneConnect.ico"));
            int count = BitConverter.ToUInt16(ico, 4), best = -1, bestWidth = 0;
            for (int i = 0; i < count; i++)
            {
                int width = ico[6 + 16 * i] == 0 ? 256 : ico[6 + 16 * i];
                bool better = best < 0 || (bestWidth < size ? width > bestWidth : width >= size && width < bestWidth);
                if (better) { best = i; bestWidth = width; }
            }
            if (best >= 0)
            {
                int length = BitConverter.ToInt32(ico, 6 + 16 * best + 8);
                int offset = BitConverter.ToInt32(ico, 6 + 16 * best + 12);
                using (var png = new MemoryStream(ico, offset, length))
                using (var image = Image.FromStream(png))
                    return new Bitmap(image);
            }
        }
        catch (Exception) { }
        return Icon.ExtractAssociatedIcon(Application.ExecutablePath).ToBitmap();
    }

    // PhoneConnect.sh refreshes <status file>.alive every 0.5 s while it runs
    bool PhoneConnectRunning()
    {
        string alive = statusPath + ".alive";
        if (!File.Exists(alive)) return (DateTime.UtcNow - started).TotalSeconds < 5;   // not there (yet)
        return (DateTime.UtcNow - File.GetLastWriteTimeUtc(alive)).TotalSeconds < 5;
    }

    void Poll()
    {
        if (!PhoneConnectRunning()) { CloseQuietly(); return; }
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
        AskToStop();
        CloseQuietly();
    }

    // PhoneConnect.sh watches for this file and stops itself (and what it started)
    void AskToStop()
    {
        try { File.WriteAllText(statusPath + ".cancel", ""); } catch (Exception) { }
    }
}
