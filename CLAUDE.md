# PhoneConnect — notes for Claude

Read this first. It sums up how this project came about, the decisions behind it,
and the problems already solved, so they don't get re-solved (or re-broken).

## What it is

A one-click Mac and Windows app that mirrors and controls an Android phone with
[scrcpy](https://github.com/Genymobile/scrcpy). It bundles scrcpy + adb (official
scrcpy release builds, pinned and checksum-verified in `build/versions.env`), so the
end user installs nothing and never opens a terminal.

- `app/PhoneConnect.sh` — **the app, one zsh script for both OSes, identical on each,
  with no platform checks.** Mac: it's the bundle's main executable
  (`PhoneConnect.app/Contents/MacOS/PhoneConnect`). Windows: `windows/Launcher.cs` →
  `PhoneConnect.exe` (icon) starts it hidden with the bundled MSYS2 zsh
  (`{app}\shell\usr\bin\zsh.exe -f PhoneConnect.sh`, env `LANG=C.UTF-8`,
  `MSYS2_ARG_CONV_EXCL=*`). `windows/installer.iss` → Inno Setup installer.
- `platform/macos/*.sh`, `platform/windows/*.sh` — everything OS-specific, same names and
  interfaces on both, packaged next to the script as `platform/`. The script sources
  `env.sh` and runs the rest as `zsh -f platform/<name>.sh …` (logged):
  `env.sh` (paths, tools, files, `OS_INFO`), `unquarantine`, `ask_question`,
  `choose_item`, `show_alert`, `run_with_timeout`, `port_open`, `run_scrcpy`,
  `picture_up`, `stop_scrcpy`, `bring_to_front`. Anything new that differs per OS goes
  in a new platform script, never an `if` in the main script.
- Windows platform scripts use PowerShell snippets via `run_ps` (`_windows.sh`): code
  written to a temp `.ps1`, data passed only in `PC_*` env vars, output forced to UTF-8.
  The PowerShell code must stay ASCII (PowerShell 5.1 reads BOM-less files as ANSI).
- Windows shell: 17 pinned MSYS2 packages (`MSYS2_PKG_*` in `build/versions.env`,
  unpacked with `zstd` — an installed one, else the pinned `ZSTD_WIN64` the build
  downloads), only `usr/bin`, `usr/lib/zsh`, `usr/share/licenses` kept.
  Paths for Windows programs (scrcpy reads `ADB`, `SCRCPY_SERVER_PATH`) via `cygpath -m`;
  MSYS process ids → Windows ids via `ps -l` (`scrcpy_winpid`).
- USB phones = `adb devices` serials that aren't `ip:port` or `_adb-tls-connect`
  (`usb_serials`). Don't use the `usb:` field of `adb devices -l`: Windows adb doesn't print it.
- Windows programs (adb.exe…) end lines with CR LF: `logged` strips `\r` from every
  captured output, so compare only output that went through `adb`/`logged`.
- `.gitattributes` keeps `*.sh` LF (zsh breaks on CRLF; the Windows runner checks out CRLF).
- Tests: `tests/run-tests.sh <platform dir>` (logic, fakes in `tests/fakes`, runs on both
  OSes in CI), `tests/windows-smoke.sh` (real Windows platform scripts, CI only).
- Builds: `build/build-macos.sh [--dev] [--run]`, `build/build-windows.ps1 [-Dev] [-Run] [-SkipInstaller]`.
- CI: `.github/workflows/build.yml` (PR builds; on main: version → build → tag
  `vX.Y.Z` → GitHub release), `version-preview.yml` (PR comment with the version).
- Versioning: `build/next-version.sh` (x.y.z from latest tag; patch by default;
  minor/major via PR form box, label `release:minor|major`, `[minor]`/`[major]` in
  commit msg, or manual run). `build/release-wanted.sh` (skip with PR box
  "Don't release", label `no-release`, or `[no release]`). `VERSION` = first version only.
- The version is substituted into the scripts at build time via `@VERSION@`.

## Scope

- Works with **any Android phone** that has USB debugging on (Android 11+ for audio).
- **Samsung DeX:** when a Samsung phone is docked and DeX is running, the app finds the
  DeX display and offers to mirror it instead of the phone screen.
- While a phone is in a USB-C dock, the phone is the USB host, so the computer can't
  reach it over USB through the dock, only over the network (the dock's Ethernet or
  Wi-Fi). A dock without a monitor needs an HDMI dummy plug for DeX to start.
- Keyboard input uses the phone's own layouts, so non-English languages work.
- Call audio can't go through scrcpy (Android blocks capturing it), so calls can be
  dialled and answered from the window but are heard on the phone or its earbuds.

## Working on this project

- **Don't change things that weren't asked for.** If a question is asked, answer it;
  don't edit files on the side. Say what you're about to change.
- **Plug and play** for the end user: download, open, done. No terminal steps, no
  `ln`, no copying scripts around. The one unavoidable step is macOS "Open Anyway"
  / Windows "Run anyway" (the app isn't signed with a paid Apple Developer ID or Windows certificate).
- Be direct and brief. Test before handing over, and say what was and wasn't tested.
- The owner pushes changes themselves; deliver changes as files/zip or
  commits on a branch for a pull request.

## Behaviour (and why) — keep these unless the user asks otherwise

Several phones are remembered, in XML: `~/.phoneconnect_phones.xml` on Mac (read with
the system's `xmllint`), `%APPDATA%\PhoneConnect\phones.xml` on Windows.
`<phone id name eth wifi>`, most recently used first.
- A phone is identified by `ro.serialno` (fallbacks `ro.boot.serialno`, `android_id`),
  not the model — two phones can be the same model. `adb get-serialno` is no good: over
  the network it returns `ip:5555`. Name = `device_name` setting, else the model.
- A known phone with a new IP is updated, never added again. An IP saved for one phone
  is removed from every other phone.
- More than one phone saved → a chooser each run: every saved phone once (a phone on USB
  is saved first, so it's in the list once, marked USB, and is the default; otherwise
  the most recently used). If the chosen phone is on USB, USB is used.
- After every network connect the phone's id is checked. If another phone answers at
  that IP, the IP is moved to that phone (added if new), taken off the chosen one, the
  connection is dropped and the next IP tried.
- First run after upgrading: the old single-phone file (`~/.phoneconnect_ips`,
  `ips.txt`) is migrated — old IPs are probed to find the phone; an IP nobody answers at
  goes to the phone found at the other one (or the single USB phone), else to a
  placeholder with an empty id that gets its real id on its first connection.

Connection, in order of preference: **USB → Ethernet → Wi-Fi**.
- While on USB (every phone plugged in): read the phone's `eth0` and `wlan0` IPs, save
  both, and turn on network mode (`adb tcpip 5555`) **only if** `service.adb.tcp.port`
  isn't already 5555 — switching restarts adbd and drops USB for a moment. Use
  `adb -s <serial>`, never `-d` (it fails with two phones plugged in).
- Network mode is lost when the phone **restarts**; then one USB plug-in is needed.
- The Ethernet IP only exists while docked (no USB then), so it's **learned over
  Wi-Fi**: when connected over Wi-Fi and `eth0` has an IP, save it and switch to it.
- Before `adb connect`, probe the port (`nc -z -G 2` on Mac, TcpClient on Windows) —
  `adb connect` to an unreachable IP can hang for over a minute.
- Disconnect stale `offline` network entries first; they cause "Server connection failed".
- Fallback: an mDNS Wireless-debugging device (`_adb-tls-connect._tcp`) whose id matches.

scrcpy options in use: `-K` (UHID keyboard: real-keyboard mode so the phone's own
layouts work, which non-English languages need; the language switch is the phone's
shortcut, and macOS's own Ctrl+Space must be turned off), `--video-codec=h265`, `--max-fps=60`,
`--max-size=1600` and 6M bitrate for the phone screen, 8M for DeX. Audio is asked
each launch. DeX = any display id other than 0 (asks DeX vs phone screen).

Things tried and **rejected**:
- `-S` (turn phone screen off): some phones (Samsung) throttle rendering → choppy.
- `-w` / `--screen-off-timeout` / changing the phone's screen timeout: left the
  phone never auto-locking after dropped connections. The user asked for **no
  timeout changes at all**. Unlocking on the phone also unlocks DeX (one lock).
- Removing `-K` in DeX mode: the language button disappeared entirely.
- Bundling via Homebrew or `~/bin` links: replaced by tools inside the app.

Watchdog: if no video frame arrives within 15 s, kill scrcpy, clear adb
forward/reverse tunnels, retry with `--force-adb-forward` (3 attempts).
This is `picture_up.sh`:
- **Mac:** detection greps scrcpy's output for `Texture`. scrcpy **buffers stdout
  when it isn't a terminal**, so `run_scrcpy.sh` runs it through `script -q /dev/null
  scrcpy …` (a pty). Without that, working sessions were killed as "stalled". Don't remove it.
- **Windows:** scrcpy shows its window only on the first frame, so success =
  `Process.MainWindowHandle != 0` (no output parsing needed). Its output reaches the log
  through a pipe, so it can arrive in bursts.

Log (`LOG_FILE`: Mac `/tmp/PhoneConnect.log`, Windows `%TEMP%\PhoneConnect.log`; the same
code on both), one file for everything, each line
`date time.ms [pid source]`: `app` = the script's messages and dialog answers, `cmd` =
every adb/tool/platform command (via `logged`, `with_timeout`, `platform`) with exit code, output (`|`) and
errors (`!`), `scrcpy` = scrcpy's own output (run with `-V debug`). Appended across runs;
lines older than 24 h are dropped at start.

Mac window: scrcpy lives in its own bundle, `tools/<arch>/PhoneConnect Mirror.app`
(`CFBundleName` PhoneConnect + icon), so the Dock shows PhoneConnect, not the "exec"
icon — a binary started directly inside a `.app` gets that bundle's identity. Started
from the background launcher it opens behind other windows, so after the first frame
`bring_to_front.sh` activates it (`NSRunningApplication … activateWithOptions` through
`osascript -l JavaScript`, no permission needed), checks `lsappinfo front`, and retries
for 5 s. A request made while the window is still starting is silently ignored.
The pid to activate is scrcpy's own, found by walking down from `$!` (`scrcpy_pid`):
`$!` is a zsh subshell, its child is `script`, and only below that is scrcpy.
Don't use System Events `set frontmost`: it needs an Automation permission prompt.
Dialogs start with `activate` so they come to the front.

## Gotchas already hit

- zsh: `"$1:$PORT"` is parsed as a history modifier (`$1:$…`) → "bad output format
  specification". Always brace: `"${1}:${PORT}"`.
- macOS apps get a minimal PATH; the scripts set PATH to the bundled tools.
  `${0:A:h}` (zsh) resolves the script's real folder.
- AppleScript-made apps ship an `Assets.car` that overrides `applet.icns` — not
  relevant now (the bundle is built by hand), but that's why an earlier icon didn't show.
- macOS quarantine: the app clears `com.apple.quarantine` from its own bundle on first
  run (after the user approved it), so the bundled scrcpy/adb aren't blocked one by one.
- Two different adb versions (Homebrew + bundled) fight over the adb server.
- GitHub ruleset on main: require PR + checks "Build macOS" and "Build Windows";
  admins (RepositoryRole id 5) may bypass. An already-imported ruleset doesn't update
  when the JSON file changes — it must be edited in Settings.

## Testing without a phone

Real tests need a real computer and phone. For logic: `zsh -f tests/run-tests.sh
platform/macos` — the real script and platform scripts with fakes for adb, scrcpy,
dialogs, port probe and picture check (`tests/fakes`); the same suite runs on Windows in
CI with the bundled zsh, plus `tests/windows-smoke.sh` for the real Windows platform
scripts (dialogs only parsed: `PC_PS_CHECK=1`). Lint: `zsh -n`, `actionlint` (with
shellcheck) for workflows, `shellcheck -x build/*.sh`.
The `.dmg`, the `.exe` compile (csc), the MSYS2 shell and Inno Setup only run on GitHub's
Mac/Windows runners (or a real Windows PC with `build\build-windows.ps1 -Dev`, which needs nothing installed).

## Status

- The first CI run (dmg, exe and installer on real runners) still needs confirming.
- The ruleset may have been imported before the admin bypass was added, in which
  case pushes to main must go through a pull request.
