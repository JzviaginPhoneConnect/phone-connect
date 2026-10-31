# PhoneConnect — notes for Claude

Read this first. It sums up how this project came about, the decisions behind it,
and the problems already solved, so they don't get re-solved (or re-broken).

## What it is

A one-click Mac and Windows app that mirrors and controls an Android phone with
[scrcpy](https://github.com/Genymobile/scrcpy). It bundles scrcpy + adb (official
scrcpy release builds, pinned and checksum-verified in `build/versions.env`), so the
end user installs nothing and never opens a terminal.

- `app/PhoneConnect.sh` — **the app, one zsh script for both OSes, identical on each,
  with no platform checks.** Mac: `PhoneConnect.app/Contents/MacOS/PhoneConnect.sh`; the
  bundle's executable `PhoneConnect` is `macos/Launcher.sh`, which `open -n`s the inner
  `Contents/Resources/PhoneConnect Run.app` (`macos/Run.sh` → execs the script) and exits.
  Needed because macOS only activates an app that's already running instead of starting it
  again, and a script started straight from the launcher is killed (TERM) by launchd when the
  launcher exits, even in its own session. Windows: `windows/Launcher.cs` →
  `PhoneConnect.exe` (icon) starts it hidden with the bundled MSYS2 zsh
  (`{app}\shell\usr\bin\zsh.exe -f PhoneConnect.sh`, env `LANG=C.UTF-8`,
  `MSYS2_ARG_CONV_EXCL=*`). `windows/installer.iss` → Inno Setup installer.
- `platform/macos/*.sh`, `platform/windows/*.sh` — everything OS-specific, same names and
  interfaces on both, packaged next to the script as `platform/`. The script sources
  `env.sh` and runs the rest as `zsh -f platform/<name>.sh …` (logged):
  `env.sh` (paths, tools, files, `OS_INFO`), `unquarantine`, `ask_question`,
  `choose_item`, `settings_form`, `show_alert`, `run_with_timeout`, `port_open`, `run_scrcpy`,
  `picture_up`, `stop_scrcpy`, `stop_previous`, `stop_tree`, `bring_to_front`, `status_window`.
- Opening the app again stops the previous run if it's still going (`stopPreviousRun`:
  pid in `$TMPDIR/PhoneConnect.pid`; TERM to its process tree so it cleans up, after 5 s
  kill whatever is left). The way out when a run hangs. The tests use their own TMPDIR for
  this reason.
- Script structure: helpers first, then one function per step, `main` at the bottom
  runs them in order, each through `step` (logs `Step start: X` / `Step end: X (N ms,
  exit R)`; steps can nest). Steps hand results over in the global variables listed at
  the top (never via their output, which `step` writes to), return 0 done / 1 failed
  (user told) / 2 cancelled, and only `main` exits. Functions are camelCase.
- Status window: the script's `showStatus "text"` appends a plain-language step to
  `$TMPDIR/PhoneConnect.<pid>.status` (and logs `Status: text`); `showStatus --done` writes
  `__done__`. The window (Mac: `macos/StatusWindow.swift` → `Contents/Resources/PhoneConnect
  Status.app`, built with swiftc for arm64+x86_64; Windows: `PhoneConnect.exe --status`)
  polls the file every 0.25 s and closes on `__done__` or when `<file>.alive` (refreshed
  every 0.5 s by a background loop in the script) goes stale for 5 s. Cancel only creates
  `<file>.cancel`; the script's loop sees it and stops the script (EXIT trap: `__done__`,
  stop a still-starting scrcpy, remove the files). Keep status lines short and
  non-technical; details go to the log.
- **The window programs must not touch other processes** (no kill/taskkill/process
  lookups). The first status-window build, whose windows killed the script's process on
  Cancel, was the first whose artifact zips (Mac and Windows) Chrome blocked as
  dangerous, and DeepInstinct flagged it; that change was the only new program in both.
  Everything that controls processes stays in the scripts. Anything new that differs per OS goes
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
  (`usbSerials`). Don't use the `usb:` field of `adb devices -l`: Windows adb doesn't print it.
- Windows programs (adb.exe…) end lines with CR LF: `runLogged` strips `\r` from every
  captured output, so compare only output that went through `adb`/`runLogged`.
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
- **Headless DeX / desktop mode (experimental):** with no external display, a phone on
  One UI 8+ (Samsung, `ro.build.version.oneui` >= 80000) or Android 16+ (others, SDK >= 36)
  is offered "DeX headless (experimental)" / "Desktop mode headless (experimental)":
  scrcpy `--new-display=1920x1080/160` and the phone renders its desktop there. Choosing it
  shows a warning (Continue / Go back, default Go back).
  - After a headless session Samsung's back gesture stays broken until SystemUI restarts
    (`am crash com.android.systemui`; works without root). It can't be avoided: in the
    phone's services.jar, `FLAG_EXTERNAL_DEX_HOSTING` is only set for TYPE_EXTERNAL (HDMI)
    displays or Miracast ones (device flag 0x4000000, WifiDisplayAdapter); a virtual
    display is always type 5 without it, whatever flags scrcpy passes.
  - The **only** things the app does to the phone: turn on `global enable_freeform_support`
    (floating windows) for the session if it's off, switch the headless display (id from
    scrcpy's "New display: … (id=N)" line) to freeform with `cmd window
    set-display-windowing-mode -d N 5` (dies with the display; without it apps open full
    screen even with freeform support on), and afterwards put the setting back and restart
    SystemUI. Windows get Samsung's pop-up view handle (menu: maximise, minimise, close,
    pin), not the DeX title bar: that's only on real DeX displays. Nothing else, and **never anything left running on the phone** (no
    background loops/watchers; the user rejected that outright).
  - Undo goes through the **task file** (`TASKS_FILE`: `~/.phoneconnect_tasks.xml` on Mac,
    `%APPDATA%\PhoneConnect\tasks.xml` on Windows; `<task phone action [namespace key value]/>`,
    meant for other kinds of tasks later). Tasks are written *before* the change, and
    removed once done. `executeTasks` (one step) runs them for every phone that has some:
    at start before the phone chooser, and after the session via `finishTasks` (in `main`
    after `runScrcpyWithRetries`; from `onExit` only if the run was stopped before that:
    Cancel, killed) when this run added tasks. `reachPhone` tries the current connection, USB, then the
    saved Ethernet and Wi-Fi IPs (a USB session whose cable was pulled still gets cleaned
    up over the network). Still unreachable → an alert: reconnect and open the app again.
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
`<phone id name eth wifi [screen audio encoder]>`, most recently used first. The
optional attributes are the settings last chosen for that phone (see Settings below).
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
shortcut, and macOS's own Ctrl+Space must be turned off), `--video-codec=… --video-encoder=…`
(from the settings), `--max-fps=60`,
`--video-codec-options=bitrate-mode:int=1` (VBR: the bit rate is an average, peaks allowed;
seemed a bit smoother when scrolling; Samsung ignores `repeat-previous-frame-after`, so the
stream is 0 fps when the screen is still),
`--max-size=1600` and 6M bitrate for the phone screen, 8M for DeX (real or headless).
DeX = any display id other than 0.

Settings: one window each launch (`askSettings`, platform `settings_form`: a pop-up
menu per group; Mac an NSAlert through AppleScriptObjC, because JXA can't make the
bold item; Windows WinForms), remembered per phone in phones.xml and the defaults next time:
- Show: phone screen / DeX / headless, only when there's a choice (saved only then, so
  an undocked phone keeps DeX). Unsaved default: DeX if connected, else the phone screen
  (headless is never the default unless saved; the warning still shows every time).
- Sound: on the phone (`--no-audio`) / on this computer (default).
- Video encoder: from `scrcpy --list-displays --list-encoders` (one call, no extra cost),
  aliases dropped, only h264/h265/av1, sorted best first and the first marked "★ best"
  (bold): hardware H.265 > H.264 > AV1, then software. Why: the Redmi A3 (MediaTek) has
  no hardware H.265 encoder; asking for h265 got Google's software `c2.android.hevc.encoder`,
  whose limits made scrcpy shrink the picture to 222x512, and it lagged. Hardware H.264
  there: 698x1600 at ~55 fps. No list → `--video-codec=h265` as before.

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
every adb/tool/platform command (via `runLogged`, `withTimeout`, `platform`) with exit code, output (`|`) and
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

## Licensing (keep complete when anything bundled changes)

- `licenses/` (GPL-3.0, LGPL-2.1/3.0, Apache-2.0, PCRE/PCRE2 BSD, SDL zlib, index README)
  ships in both apps, plus `PhoneConnect-MIT.txt` (= LICENSE) and `adb-NOTICE.txt`
  (Platform-Tools NOTICE.txt, pinned `PLATFORM_TOOLS_*` in versions.env).
- GPL/LGPL source: `build/collect-sources.sh` fetches the pinned `SOURCE_*` archives
  (scrcpy + FFmpeg/SDL/libusb at the versions in scrcpy's `app/deps/`, and every MSYS2
  package's source package); the release job publishes them once as the GitHub release
  `THIRD_PARTY_SOURCES_TAG` (not "latest"). THIRD_PARTY_NOTICES.md and README link to it;
  the release fails if the notices don't link to the current tag.
- **When scrcpy or any MSYS2 package changes:** update its `SOURCE_*` line (url, sha256),
  bump `THIRD_PARTY_SOURCES_TAG`, update the link in THIRD_PARTY_NOTICES.md and README,
  and the versions in THIRD_PARTY_NOTICES.md.
- On macOS, FFmpeg/SDL/libusb are statically linked into scrcpy (LGPL: complete source
  incl. scrcpy's build scripts is in the sources release, so relinking is possible).

## Gotchas already hit

- macOS 27.2 (installed 2026-10-29; Wi-Fi worked before it): Local Network access is judged
  by the program's own signing identifier, not the app that started it. The bundled adb
  (Google-signed, identifier `adb`, no bundle) can't show a prompt and is silently denied:
  `adb connect` → "No route to host" while `nc` (Apple, exempt) reaches the port. System
  log: `LocalNetwork: found bundle id adb by PID`, `reason: NECP`. Allowing PhoneConnect in
  Settings didn't help; ad-hoc signing with another identifier (`adb`) didn't either. The
  build re-signs adb ad hoc with identifier `io.github.phoneconnect`, so it uses
  PhoneConnect's permission (user must allow PhoneConnect under Local Network; whether
  macOS prompts on its own for a fresh install is untested).

- adb's own macOS USB code can hang for good while its server starts (a USB-C dock here:
  stuck in `IOServiceOpen` on one of the dock's devices, no phone on USB), and
  `adb start-server` waits forever. `startAdbServer` gives each try 10 s, then retries with
  `ADB_LIBUSB=1` (still sees USB phones), then `ADB_USB=0` (network only), else an alert.
  Both worked on that Mac. A server started that way keeps running for later runs.

- zsh's `BG_NICE` (on by default) runs every `&` job at nice 5. scrcpy is started with `&`
  (for the watchdog), so it ran at lowered priority and mirroring stuttered on the Mac,
  less smooth than Windows in a VM on the same Mac. `setopt NO_BG_NICE` at the top of the
  script fixes it; a test checks scrcpy's nice level is 0.

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
