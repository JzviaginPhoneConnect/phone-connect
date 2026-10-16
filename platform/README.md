# Platform scripts

`app/PhoneConnect.sh` is the same file on macOS and Windows and never checks which OS
it's on. Everything that differs is one of the scripts below. Each OS has its own
folder with the **same file names and the same interface**; the build copies the right
folder next to the app script as `platform/`.

The app sources `env.sh` and runs every other script as `zsh -f platform/<name>.sh …`,
writing the call, its exit code and its output to the log. Arguments go in, the result
comes out on stdout, success or failure is the exit code.

| Script | Arguments → result | macOS | Windows |
|---|---|---|---|
| `env.sh` (sourced) | sets `TOOLS_DIR ADB SCRCPY SCRCPY_SERVER_PATH PHONES_FILE OLD_IPS_FILE LOG_FILE TMPDIR OS_INFO`, `PATH` | bundle paths, `~/.phoneconnect_phones.xml`, `/tmp/PhoneConnect.log` | `{app}\tools`, `%APPDATA%\PhoneConnect\phones.xml`, `%TEMP%\PhoneConnect.log` |
| `unquarantine.sh` | — | `xattr -dr com.apple.quarantine` on the bundle | `Unblock-File` on the app folder, once per version |
| `ask_question.sh` | `text button1 button2` → the button, empty = Cancel | `osascript display dialog` | WinForms dialog |
| `choose_item.sh` | `prompt default item…` → the item, empty = Cancel | `osascript choose from list` | WinForms list |
| `show_alert.sh` | `title message`, waits for OK | `osascript display alert` | MessageBox |
| `run_with_timeout.sh` | `seconds command…` → the command's output and exit code | `perl` alarm | `timeout` |
| `port_open.sh` | `ip port` → exit 0 if something answers (≤ 2 s) | `nc -z -G 2` | `TcpClient`, 2 s |
| `run_scrcpy.sh` | `scrcpy args…`, runs in the foreground (the app starts it in the background) | through `script` (a pty, so output isn't buffered) | `scrcpy.exe` directly |
| `picture_up.sh` | `pid output-file` → exit 0 once the picture shows | `Texture` in the output | the scrcpy window exists |
| `stop_scrcpy.sh` | `pid` | `pkill -P`, `kill` | `taskkill /T /F` |
| `status_window.sh` | `status-file pid` → opens the status window and returns at once | `open -n` the bundle's `PhoneConnect Status.app` (`macos/StatusWindow.swift`) | `PhoneConnect.exe --status` (`windows/Launcher.cs`), with the Windows pid |
| `bring_to_front.sh` | `pid` → exit 0 when scrcpy's window is in front | activate via AppKit, check with `lsappinfo` | nothing (already in front) |

`windows/_windows.sh` holds helpers for the Windows scripts only: `run_ps` (runs a
PowerShell snippet hidden; data goes in through `PC_*` environment variables, output
comes back as UTF-8) and `scrcpy_winpid` (MSYS process id → Windows process id).

To add something OS-specific: add a script with the same name to both folders, and
call it from the app with `platform <name> …`.
