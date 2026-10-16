// A stand-in for scrcpy's window in the Windows smoke test: shows a window for 60 s.
// Compiled as scrcpy.exe, so the platform scripts find it by name.
using System;
using System.Windows.Forms;
static class FakeWindow
{
    [STAThread]
    static void Main()
    {
        Console.WriteLine("INFO: Texture: 1080x2340");
        var form = new Form { Text = "PhoneConnect test window" };
        var timer = new Timer { Interval = 60000 };
        timer.Tick += (s, e) => form.Close();
        timer.Start();
        Application.Run(form);
    }
}
