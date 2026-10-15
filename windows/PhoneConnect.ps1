# PhoneConnect (Windows) — mirror and control an Android phone with scrcpy.
# Same behaviour as the macOS version:
#   * asks whether to mirror DeX (if a DeX display exists) and whether to forward audio
#   * connects over USB, Ethernet (dock) or Wi-Fi, in that order of preference
#   * remembers the phone's Ethernet and Wi-Fi IPs, so the cable is only needed
#     once after each phone restart
#   * restarts scrcpy if no picture arrives within 15 seconds
# Normally started by PhoneConnect.exe (no console window). Any extra arguments
# are passed straight to scrcpy.
# Written for Windows PowerShell 5.1, which every Windows 10/11 has.

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ExtraArgs = @())

$ErrorActionPreference = 'Continue'

# The build replaces @VERSION@ with the release version (e.g. 1.2.3).
$AppVersion = '@VERSION@'

# ---- Paths: everything ships next to this script, nothing has to be installed ----
$AppDir   = $PSScriptRoot
$Tools    = Join-Path $AppDir 'tools'
$Adb      = Join-Path $Tools 'adb.exe'
$Scrcpy   = Join-Path $Tools 'scrcpy.exe'
$env:ADB  = $Adb                                       # the adb scrcpy should use
$env:SCRCPY_SERVER_PATH = Join-Path $Tools 'scrcpy-server'  # the part that runs on the phone

$DataDir  = Join-Path $env:APPDATA 'PhoneConnect'
$IpsFile  = Join-Path $DataDir 'ips.txt'               # lines: "eth <ip>" and "wifi <ip>"
$LogFile  = Join-Path $env:TEMP 'PhoneConnect.log'
$Port     = 5555
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
Set-Content -Path $LogFile -Value '' -Encoding UTF8

function Log([string]$msg) {
  $line = '{0:HH:mm:ss} {1}' -f (Get-Date), $msg
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
  Write-Host $line
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$IconPath = Join-Path $AppDir 'PhoneConnect.ico'
$AppIcon  = $null
if (Test-Path $IconPath) { try { $AppIcon = New-Object System.Drawing.Icon $IconPath } catch {} }

function Show-Error([string]$title, [string]$text) {
  Log "ERROR: $title - $text"
  [void][System.Windows.Forms.MessageBox]::Show($text, "PhoneConnect $AppVersion - $title", 'OK', 'Warning')
}

# A small dialog with the app's own button labels (MessageBox only offers Yes/No).
# Returns the clicked button's text, or '' for Cancel / closing the window.
function Ask([string]$text, [string]$button1, [string]$button2) {
  $form = New-Object System.Windows.Forms.Form
  $form.Text = "PhoneConnect $AppVersion"
  $form.FormBorderStyle = 'FixedDialog'
  $form.StartPosition = 'CenterScreen'
  $form.MaximizeBox = $false
  $form.MinimizeBox = $false
  $form.TopMost = $true
  $form.AutoSize = $true
  $form.AutoSizeMode = 'GrowAndShrink'
  $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
  if ($AppIcon) { $form.Icon = $AppIcon }

  $outer = New-Object System.Windows.Forms.FlowLayoutPanel
  $outer.FlowDirection = 'TopDown'
  $outer.AutoSize = $true
  $outer.AutoSizeMode = 'GrowAndShrink'
  $outer.Padding = New-Object System.Windows.Forms.Padding(16)

  $label = New-Object System.Windows.Forms.Label
  $label.Text = $text
  $label.AutoSize = $true
  $label.MaximumSize = New-Object System.Drawing.Size(400, 0)
  $label.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)
  $outer.Controls.Add($label)

  $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
  $buttons.FlowDirection = 'LeftToRight'
  $buttons.AutoSize = $true
  $buttons.AutoSizeMode = 'GrowAndShrink'
  $buttons.Anchor = 'Right'
  foreach ($caption in @('Cancel', $button1, $button2)) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $caption
    $b.AutoSize = $true
    $b.MinimumSize = New-Object System.Drawing.Size(100, 32)
    $b.Add_Click({ $f = $this.FindForm(); $f.Tag = $this.Text; $f.Close() })
    $buttons.Controls.Add($b)
    if ($caption -eq $button2) { $form.AcceptButton = $b }
    if ($caption -eq 'Cancel') { $form.CancelButton = $b }
  }
  $outer.Controls.Add($buttons)
  $form.Controls.Add($outer)
  $form.Add_Shown({ $this.Activate() })
  [void]$form.ShowDialog()
  $answer = [string]$form.Tag
  $form.Dispose()
  if ($answer -eq 'Cancel') { return '' }
  return $answer
}

# Windows quotes command-line arguments by hand; this follows the usual rules.
function Quote-Arg([string]$a) {
  if ($a -eq '') { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  $escaped = ($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1'
  return '"' + $escaped + '"'
}

# Run a tool, return its output (stdout + stderr). Gives up after $TimeoutSec,
# so an unreachable phone can never hang the app.
function Invoke-Tool([string]$Exe, [string[]]$ArgList, [int]$TimeoutSec = 15) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.Arguments = ($ArgList | ForEach-Object { Quote-Arg $_ }) -join ' '
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  try { $p = [System.Diagnostics.Process]::Start($psi) } catch { Log "Could not run $Exe : $_"; return '' }
  $out = $p.StandardOutput.ReadToEndAsync()
  $err = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    try { $p.Kill() } catch {}
    return ''
  }
  return ($out.Result + $err.Result)
}

function Adb([string[]]$ArgList, [int]$TimeoutSec = 15) { Invoke-Tool $Adb $ArgList $TimeoutSec }

# The first adb call starts adb's background server. Start it on its own,
# without capturing output, so it can't hold our pipes open.
function Start-AdbServer {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Adb
  $psi.Arguments = 'start-server'
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  try { $p = [System.Diagnostics.Process]::Start($psi); [void]$p.WaitForExit(20000) } catch {}
}

# ---- Small helpers around adb ----

# Rows of `adb devices` as objects: Serial, State
function Get-Devices {
  $rows = @()
  foreach ($line in ((Adb @('devices')) -split "`r?`n")) {
    if ($line -match '^(\S+)\s+(device|offline|unauthorized|authorizing|no permissions)') {
      $rows += [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] }
    }
  }
  return $rows
}

function Is-NetworkSerial([string]$s) { return ($s -match ':\d+$') -or ($s -match '_adb-tls-connect') }

# The phone connected by cable, if any (network ones have IP:PORT or mDNS names)
function Get-UsbSerial {
  foreach ($d in Get-Devices) {
    if ($d.State -eq 'device' -and -not (Is-NetworkSerial $d.Serial)) { return $d.Serial }
  }
  return $null
}

function Get-IfaceIp([string]$serial, [string]$iface) {
  $out = Adb @('-s', $serial, 'shell', 'ip', '-f', 'inet', 'addr', 'show', $iface) 8
  if ($out -match 'inet (\d+\.\d+\.\d+\.\d+)/') { return $Matches[1] }
  return ''
}

function Get-SavedIp([string]$kind) {
  if (-not (Test-Path $IpsFile)) { return '' }
  foreach ($line in Get-Content $IpsFile) {
    $parts = $line -split '\s+'
    if ($parts.Count -ge 2 -and $parts[0] -eq $kind) { return $parts[1] }
  }
  return ''
}

# Save both IPs; keeps the old value when a new one is empty
# (e.g. no Ethernet IP while the phone isn't docked).
function Save-Ips([string]$eth, [string]$wifi) {
  if (-not $eth)  { $eth  = Get-SavedIp 'eth' }
  if (-not $wifi) { $wifi = Get-SavedIp 'wifi' }
  $lines = @()
  if ($eth)  { $lines += "eth $eth" }
  if ($wifi) { $lines += "wifi $wifi" }
  Set-Content -Path $IpsFile -Value $lines -Encoding ASCII
}

# Quick check that something answers at IP:PORT (about 2 s, never hangs)
function Test-PortOpen([string]$ip) {
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $task = $client.ConnectAsync($ip, $Port)
    if ($task.Wait(2000)) { return $client.Connected }
    return $false
  } catch { return $false } finally { $client.Close() }
}

$script:Serial = $null
$script:Link   = $null

# Connect to IP:PORT over the network; sets $script:Serial on success
function Try-Connect([string]$ip) {
  if (-not (Test-PortOpen $ip)) { Log "  $ip not reachable"; return $false }
  $target = "${ip}:$Port"
  for ($i = 0; $i -lt 2; $i++) {
    [void](Adb @('disconnect', $target) 5)       # clear any stale/offline entry
    [void](Adb @('connect', $target) 8)
    for ($j = 0; $j -lt 3; $j++) {
      $row = Get-Devices | Where-Object { $_.Serial -eq $target }
      if ($row -and $row.State -eq 'device') { $script:Serial = $target; return $true }
      Start-Sleep -Seconds 1
    }
  }
  [void](Adb @('disconnect', $target) 5)
  return $false
}

function Wait-UsbReady([string]$serial) {
  for ($i = 0; $i -lt 10; $i++) {
    if ((Adb @('-s', $serial, 'get-state') 5).Trim() -eq 'device') { return $true }
    Start-Sleep -Seconds 1
  }
  return $false
}

# ===================================================================
Log "PhoneConnect $AppVersion starting"

# A downloaded zip marks every file as "from the internet"; clear that from our
# own files so Windows doesn't block the bundled tools.
Get-ChildItem -Path $AppDir -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

foreach ($t in @($Adb, $Scrcpy)) {
  if (-not (Test-Path $t)) { Show-Error 'missing files' "$t is missing. Please reinstall PhoneConnect."; exit 1 }
}

Start-AdbServer

# Drop network entries stuck "offline" (e.g. from an old IP)
foreach ($d in Get-Devices) {
  if ($d.State -eq 'offline' -and (Is-NetworkSerial $d.Serial)) { [void](Adb @('disconnect', $d.Serial) 5) }
}

# ---- Pick the connection. Priority: 1. USB  2. Ethernet (dock)  3. Wi-Fi ----
$usb = Get-UsbSerial
if (-not $usb) { Start-Sleep -Seconds 2; $usb = Get-UsbSerial }   # it can vanish for a moment

if ($usb) {
  # ---- 1. USB ----
  [void](Wait-UsbReady $usb)
  $ethNow  = Get-IfaceIp $usb 'eth0'
  $wifiNow = Get-IfaceIp $usb 'wlan0'
  Save-Ips $ethNow $wifiNow
  Log ("Saved IPs - Ethernet: {0}, Wi-Fi: {1}" -f ($(if ($ethNow) { $ethNow } else { 'none' })), ($(if ($wifiNow) { $wifiNow } else { 'none' })))

  # Turn on network mode for later cable-free launches (only if it's off,
  # because switching it restarts adb on the phone)
  $tcpPort = (Adb @('-s', $usb, 'shell', 'getprop', 'service.adb.tcp.port') 8).Trim()
  if ($tcpPort -ne "$Port") {
    Log "Turning on network mode (port $Port)"
    [void](Adb @('-s', $usb, 'tcpip', "$Port") 10)
    Start-Sleep -Seconds 3
    [void](Wait-UsbReady $usb)
  }
  $script:Serial = $usb
  $script:Link = 'USB'
} else {
  # ---- 2. Ethernet, 3. Wi-Fi ----
  foreach ($kind in @('eth', 'wifi')) {
    $ip = Get-SavedIp $kind
    if (-not $ip) { continue }
    Log "Trying $kind at $ip..."
    if (Try-Connect $ip) {
      $script:Link = $(if ($kind -eq 'eth') { 'Ethernet' } else { 'Wi-Fi' })
      break
    }
  }

  # Fallback: a phone connected through Android's Wireless debugging (found automatically)
  if (-not $script:Serial) {
    $wd = Get-Devices | Where-Object { $_.State -eq 'device' -and $_.Serial -match '_adb-tls-connect' } | Select-Object -First 1
    if ($wd) { $script:Serial = $wd.Serial; $script:Link = 'Wireless debugging' }
  }

  if (-not $script:Serial) {
    Show-Error 'no phone found' ("Plug the phone in with a USB cable once (needed after every phone restart) " +
      "so PhoneConnect can turn on network mode. Make sure USB debugging is on and you tapped Allow on the phone.")
    exit 1
  }

  # Refresh the saved IPs. This is also how the Ethernet IP gets learned: it only
  # exists while docked, and then there's no USB, so it's read over Wi-Fi.
  $ethNow = Get-IfaceIp $script:Serial 'eth0'
  Save-Ips $ethNow (Get-IfaceIp $script:Serial 'wlan0')

  # Docked but we came in over Wi-Fi: switch this session to Ethernet
  if ($ethNow -and $script:Link -ne 'Ethernet') {
    $prev = $script:Serial
    Log "Phone has Ethernet ($ethNow) - switching to it"
    if (Try-Connect $ethNow) { $script:Link = 'Ethernet' }
    else { $script:Serial = $prev; Log "Ethernet not reachable, staying on $($script:Link)" }
  }
}
Log "Connection: $($script:Link) ($($script:Serial))"
$Serial = $script:Serial
$Link = $script:Link

# ---- DeX (external) display: any display other than 0 ----
$dexId = $null
$displays = Invoke-Tool $Scrcpy @('-s', $Serial, '--list-displays') 20
foreach ($m in [regex]::Matches($displays, '--display-id=(\d+)')) {
  if ($m.Groups[1].Value -ne '0') { $dexId = $m.Groups[1].Value; break }
}

$target = 'phone'
if ($dexId) {
  $choice = Ask 'A DeX display is connected. What do you want to mirror?' 'Phone screen' 'DeX'
  if (-not $choice) { exit 0 }
  if ($choice -eq 'DeX') { $target = 'dex' }
}

# ---- Audio ----
$choice = Ask "Play the phone's sound on this computer?`n`n(While on, the phone's own speaker is muted.)" 'No audio' 'With audio'
if (-not $choice) { exit 0 }
$audio = @()
if ($choice -ne 'With audio') { $audio = @('--no-audio') }

# ---- Start scrcpy and watch it ----
# Over the network scrcpy sometimes starts on the phone and then stalls with no
# picture. scrcpy only shows its window once the first frame arrives, so if no
# window appears within 15 s, kill it, clear the tunnels and retry (3 attempts).
function Run-Scrcpy([string[]]$ScrcpyArgs) {
  $extra = @()
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Scrcpy
    $psi.Arguments = (($extra + $ScrcpyArgs) | ForEach-Object { Quote-Arg $_ }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true            # no console window; scrcpy's own window still shows
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $Tools
    Log "Starting: scrcpy $($psi.Arguments)"
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()

    $ok = $false
    for ($t = 0; $t -lt 15; $t++) {
      Start-Sleep -Seconds 1
      $p.Refresh()
      if ($p.HasExited) { break }
      if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $ok = $true; break }   # picture is up
    }

    if ($ok) {
      Log 'Picture is up'
      $p.WaitForExit()
      Add-Content -Path $LogFile -Value ($out.Result + $err.Result) -Encoding UTF8
      exit $p.ExitCode
    }

    if (-not $p.HasExited) { try { $p.Kill() } catch {} ; [void]$p.WaitForExit(3000) }
    Add-Content -Path $LogFile -Value ($out.Result + $err.Result) -Encoding UTF8
    if ($attempt -lt 3) { Log "scrcpy didn't connect (attempt $attempt of 3) - retrying" }
    else { Log "scrcpy didn't connect (attempt 3 of 3) - giving up" }
    [void](Adb @('-s', $Serial, 'forward', '--remove-all') 5)
    [void](Adb @('-s', $Serial, 'reverse', '--remove-all') 5)
    $extra = @('--force-adb-forward')
    Start-Sleep -Seconds 1
  }
  Show-Error "couldn't start" "No picture after 3 tries. Details are in $LogFile"
  exit 1
}

# -K = act as a real keyboard, so the phone's own layouts (e.g. Hebrew) work
$common = @('-K', '--video-codec=h265', '--max-fps=60') + $audio
if ($target -eq 'dex') {
  Log "Mirroring DeX (display $dexId), audio: $choice"
  Run-Scrcpy (@('-s', $Serial, "--display-id=$dexId") + $common + @('--video-bit-rate=8M', "--window-title=PhoneConnect - DeX ($Link)") + $ExtraArgs)
} else {
  Log "Mirroring phone screen, audio: $choice"
  Run-Scrcpy (@('-s', $Serial) + $common + @('--max-size=1600', '--video-bit-rate=6M', "--window-title=PhoneConnect ($Link)") + $ExtraArgs)
}
