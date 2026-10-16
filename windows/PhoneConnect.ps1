# PhoneConnect (Windows) — mirror and control an Android phone with scrcpy.
# Same behaviour as the macOS version:
#   * remembers several phones; asks which one to use when more than one is known
#   * asks whether to mirror DeX (if a DeX display exists) and whether to forward audio
#   * connects over USB, Ethernet (dock) or Wi-Fi, in that order of preference
#   * remembers each phone's Ethernet and Wi-Fi IPs, so the cable is only needed
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
$PhonesFile = Join-Path $DataDir 'phones.xml'          # the saved phones (see "Saved phones")
$OldIpsFile = Join-Path $DataDir 'ips.txt'             # older versions: lines "eth <ip>" and "wifi <ip>"
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

# A list to pick from. Returns the chosen item, or '' for Cancel / closing the window.
function Choose([string]$text, [string[]]$items, [string]$default) {
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
  $label.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  $outer.Controls.Add($label)

  $list = New-Object System.Windows.Forms.ListBox
  $list.Name = 'list'
  $list.Width = 400
  $list.Font = $form.Font
  $list.IntegralHeight = $true
  $list.Items.AddRange([object[]]$items)
  $list.Height = [Math]::Min($items.Count, 10) * $list.ItemHeight + 6
  $list.SelectedItem = $default
  if ($list.SelectedIndex -lt 0) { $list.SelectedIndex = 0 }
  $list.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)
  $list.Add_DoubleClick({ $f = $this.FindForm(); $f.Tag = [string]$this.SelectedItem; $f.Close() })
  $outer.Controls.Add($list)

  $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
  $buttons.FlowDirection = 'LeftToRight'
  $buttons.AutoSize = $true
  $buttons.AutoSizeMode = 'GrowAndShrink'
  $buttons.Anchor = 'Right'
  foreach ($caption in @('Cancel', 'Connect')) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $caption
    $b.AutoSize = $true
    $b.MinimumSize = New-Object System.Drawing.Size(100, 32)
    if ($caption -eq 'Connect') {
      $b.Add_Click({ $f = $this.FindForm(); $f.Tag = [string]$f.Controls.Find('list', $true)[0].SelectedItem; $f.Close() })
      $form.AcceptButton = $b
    } else {
      $b.Add_Click({ $f = $this.FindForm(); $f.Tag = ''; $f.Close() })
      $form.CancelButton = $b
    }
    $buttons.Controls.Add($b)
  }
  $outer.Controls.Add($buttons)
  $form.Controls.Add($outer)
  $form.Add_Shown({ $this.Activate() })
  [void]$form.ShowDialog()
  $answer = [string]$form.Tag
  $form.Dispose()
  return $answer
}

# Windows quotes command-line arguments by hand; this follows the usual rules.
function Quote-Arg([string]$a) {
  if ($a -eq '') { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  $escaped = ($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1'
  return '"' + $escaped + '"'
}

# Run a tool, return its output (stdout + stderr, or only stdout with $StdoutOnly).
# Gives up after $TimeoutSec, so an unreachable phone can never hang the app.
function Invoke-Tool([string]$Exe, [string[]]$ArgList, [int]$TimeoutSec = 15, [bool]$StdoutOnly = $false) {
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
  if ($StdoutOnly) { return $out.Result }
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

# The phones connected by cable (network ones have IP:PORT or mDNS names)
function Get-UsbSerials {
  return @(Get-Devices | Where-Object { -not (Is-NetworkSerial $_.Serial) } | ForEach-Object { $_.Serial })
}

function Get-IfaceIp([string]$serial, [string]$iface) {
  $out = Adb @('-s', $serial, 'shell', 'ip', '-f', 'inet', 'addr', 'show', $iface) 8
  if ($out -match 'inet (\d+\.\d+\.\d+\.\d+)/') { return $Matches[1] }
  return ''
}

# One line of a shell command's output ('' for "null"/"unknown" or an error)
function Get-PhoneProp([string]$serial, [string[]]$cmd) {
  $out = Invoke-Tool $Adb (@('-s', $serial, 'shell') + $cmd) 8 $true
  $v = ((($out -split "`r?`n") | Select-Object -First 1) -replace "`t", ' ').Trim()
  if ($v -eq 'null' -or $v -eq 'unknown') { return '' }
  return $v
}

# The phone's own serial number: the same over USB and the network, and different
# for two phones of the same model
function Get-PhoneId([string]$serial) {
  $id = Get-PhoneProp $serial @('getprop', 'ro.serialno')
  if (-not $id) { $id = Get-PhoneProp $serial @('getprop', 'ro.boot.serialno') }
  if (-not $id) { $id = Get-PhoneProp $serial @('settings', 'get', 'secure', 'android_id') }
  return $id
}

# The name set on the phone, else its model
function Get-PhoneName([string]$serial) {
  $name = Get-PhoneProp $serial @('settings', 'get', 'global', 'device_name')
  if (-not $name) { $name = Get-PhoneProp $serial @('getprop', 'ro.product.model') }
  if (-not $name) { $name = 'Phone' }
  return $name
}

# ---- Saved phones ----
# One entry per phone, told apart by its serial number (not the model, since two
# phones can be the same model), with its last known Ethernet and Wi-Fi IPs.
# Most recently used first. The empty id is a phone saved by an older version
# whose serial isn't known yet; it gets its real id on the first connection.
$script:Phones = New-Object 'System.Collections.Generic.List[object]'

function New-Phone([string]$id, [string]$name, [string]$eth, [string]$wifi) {
  return [pscustomobject]@{ Id = $id; Name = $name; Eth = $eth; Wifi = $wifi }
}

function Load-Phones {
  $script:Phones.Clear()
  if (-not (Test-Path $PhonesFile)) { return }
  try { $doc = New-Object System.Xml.XmlDocument; $doc.Load($PhonesFile) }
  catch { Log "Couldn't read $PhonesFile : $_"; return }
  foreach ($e in $doc.SelectNodes('/phones/phone')) {
    $script:Phones.Add((New-Phone $e.GetAttribute('id') $e.GetAttribute('name') $e.GetAttribute('eth') $e.GetAttribute('wifi')))
  }
}

function Write-Phones {
  # An old-version phone with no IPs left has nothing to remember
  for ($i = $script:Phones.Count - 1; $i -ge 0; $i--) {
    $p = $script:Phones[$i]
    if (-not $p.Id -and -not $p.Eth -and -not $p.Wifi) { $script:Phones.RemoveAt($i) }
  }
  $doc = New-Object System.Xml.XmlDocument
  [void]$doc.AppendChild($doc.CreateXmlDeclaration('1.0', 'UTF-8', $null))
  $root = $doc.CreateElement('phones')
  [void]$doc.AppendChild($root)
  foreach ($p in $script:Phones) {
    $e = $doc.CreateElement('phone')
    $e.SetAttribute('id', [string]$p.Id)
    $e.SetAttribute('name', [string]$p.Name)
    $e.SetAttribute('eth', [string]$p.Eth)
    $e.SetAttribute('wifi', [string]$p.Wifi)
    [void]$root.AppendChild($e)
  }
  $tmp = "$PhonesFile.tmp"
  $doc.Save($tmp)
  Move-Item -Force -Path $tmp -Destination $PhonesFile
}

function Find-PhoneIndex([string]$id) {
  for ($i = 0; $i -lt $script:Phones.Count; $i++) {
    if ($script:Phones[$i].Id -eq $id) { return $i }
  }
  return -1
}

function Get-SavedName([string]$id) {
  $i = Find-PhoneIndex $id
  if ($i -ge 0) { return $script:Phones[$i].Name }
  return ''
}

# Add the phone (at the end) or update it (an empty value keeps the saved one,
# e.g. no Ethernet IP while undocked), and take its IPs off any other phone
# (the network gave them to this one).
function Save-Phone([string]$id, [string]$name, [string]$eth, [string]$wifi) {
  $idx = Find-PhoneIndex $id
  if ($idx -lt 0) { $script:Phones.Add((New-Phone $id '' '' '')); $idx = $script:Phones.Count - 1 }
  for ($i = 0; $i -lt $script:Phones.Count; $i++) {
    if ($i -eq $idx) { continue }
    $p = $script:Phones[$i]
    if ($p.Eth  -and ($p.Eth  -eq $eth -or $p.Eth  -eq $wifi)) { $p.Eth  = '' }
    if ($p.Wifi -and ($p.Wifi -eq $eth -or $p.Wifi -eq $wifi)) { $p.Wifi = '' }
  }
  $p = $script:Phones[$idx]
  if ($name) { $p.Name = $name }
  if ($eth)  { $p.Eth  = $eth }
  if ($wifi) { $p.Wifi = $wifi }
  Write-Phones
}

# Move the phone to the top (the default next time)
function Set-PhoneUsed([string]$id) {
  $idx = Find-PhoneIndex $id
  if ($idx -lt 0) { return }
  $p = $script:Phones[$idx]
  $script:Phones.RemoveAt($idx)
  $script:Phones.Insert(0, $p)
  Write-Phones
}

function Forget-Ip([string]$id, [string]$ip) {
  $idx = Find-PhoneIndex $id
  if ($idx -lt 0) { return }
  $p = $script:Phones[$idx]
  if ($p.Eth  -eq $ip) { $p.Eth  = '' }
  if ($p.Wifi -eq $ip) { $p.Wifi = '' }
  Write-Phones
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

# Read which phone is at $serial and its current IPs, and save them.
# $ip/$kind: the IP we came in on, in case the phone didn't report it.
# Sets $script:LearnedId, LearnedName, LearnedEth.
function Learn-Phone([string]$serial, [string]$fallbackId, [string]$ip = '', [string]$kind = '') {
  $id = Get-PhoneId $serial
  if (-not $id) { $id = $fallbackId }
  $name = Get-PhoneName $serial
  $eth  = Get-IfaceIp $serial 'eth0'
  $wifi = Get-IfaceIp $serial 'wlan0'
  if ($ip -and $ip -ne $eth -and $ip -ne $wifi) {
    if ($kind -eq 'eth') { if (-not $eth) { $eth = $ip } } elseif (-not $wifi) { $wifi = $ip }
  }
  $script:LearnedId = $id
  $script:LearnedName = $name
  $script:LearnedEth = $eth
  Save-Phone $id $name $eth $wifi
}

# $script:Serial is a new network connection. True if the wanted phone answered.
# If a different phone has this IP now, the IP is moved to that phone (it's
# added if it's new) and the connection dropped.
function Claim-Connection([string]$want, [string]$ip, [string]$kind) {
  Learn-Phone $script:Serial $want $ip $kind
  if (-not $want -and $script:LearnedId) {
    # A phone saved by an older version: now we know which one it is
    $ph = Find-PhoneIndex ''
    if ($ph -ge 0) {
      $old = $script:Phones[$ph]
      $p = $script:Phones[(Find-PhoneIndex $script:LearnedId)]
      if (-not $p.Eth)  { $p.Eth  = $old.Eth }
      if (-not $p.Wifi) { $p.Wifi = $old.Wifi }
      [void]$script:Phones.Remove($old)
      Write-Phones
    }
    $script:ChosenId = $script:LearnedId
    return $true
  }
  if ($script:LearnedId -eq $want) { return $true }
  Log "  $ip is now another phone ($($script:LearnedName)) - moved the IP to it, disconnecting"
  Forget-Ip $want $ip
  [void](Adb @('disconnect', $script:Serial) 5)
  $script:Serial = $null
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

# ---- Phones on USB ----
# For each phone plugged in: save its Ethernet and Wi-Fi IPs and turn on network
# mode, so later launches can connect without the cable (until the phone restarts).
Load-Phones
$migrate = (-not (Test-Path $PhonesFile)) -and (Test-Path $OldIpsFile)
$usbOf = @{}      # phone id -> USB serial

$usbList = Get-UsbSerials
if (-not $usbList) { Start-Sleep -Seconds 2; $usbList = Get-UsbSerials }   # it can vanish for a moment

foreach ($usb in $usbList) {
  if (-not (Wait-UsbReady $usb)) { Log "USB phone $usb isn't ready (tap Allow on the phone?) - skipping it"; continue }
  Learn-Phone $usb $usb
  $usbOf[$script:LearnedId] = $usb
  $p = $script:Phones[(Find-PhoneIndex $script:LearnedId)]
  Log ("USB: {0} ({1}) - saved IPs - Ethernet: {2}, Wi-Fi: {3}" -f $p.Name, $p.Id, ($(if ($p.Eth) { $p.Eth } else { 'none' })), ($(if ($p.Wifi) { $p.Wifi } else { 'none' })))

  # Turn on network mode for later cable-free launches (only if it's off,
  # because switching it restarts adb on the phone)
  $tcpPort = (Adb @('-s', $usb, 'shell', 'getprop', 'service.adb.tcp.port') 8).Trim()
  if ($tcpPort -ne "$Port") {
    Log "Turning on network mode (port $Port)"
    [void](Adb @('-s', $usb, 'tcpip', "$Port") 10)
    Start-Sleep -Seconds 3
    [void](Wait-UsbReady $usb)
  }
}

# ---- First run of this version: move the IPs saved by an older version ----
# They didn't record which phone they belong to, so ask whoever answers there.
# The old file only ever held one phone's IPs, so an IP nobody answers at goes
# to the phone found at the other IP (or the one plugged in by USB).
if ($migrate) {
  Log "Moving saved IPs from $OldIpsFile to $PhonesFile"
  $oldEth = ''; $oldWifi = ''; $oldOwner = $null
  foreach ($line in Get-Content $OldIpsFile) {
    $parts = $line -split '\s+'
    if ($parts.Count -lt 2 -or -not $parts[1] -or ($parts[0] -ne 'eth' -and $parts[0] -ne 'wifi')) { continue }
    $kind = $parts[0]; $ip = $parts[1]
    $known = $script:Phones | Where-Object { $_.Eth -eq $ip -or $_.Wifi -eq $ip } | Select-Object -First 1
    if ($known) { if ($null -eq $oldOwner) { $oldOwner = $known.Id }; continue }   # already known from USB
    Log "Checking which phone is at $ip..."
    if (Try-Connect $ip) {
      Learn-Phone $script:Serial '' $ip $kind
      if ($null -eq $oldOwner) { $oldOwner = $script:LearnedId }
      $script:Serial = $null
    } elseif ($kind -eq 'eth') { $oldEth = $ip } else { $oldWifi = $ip }
  }
  if ($null -eq $oldOwner -and $usbOf.Count -eq 1) { $oldOwner = @($usbOf.Keys)[0] }
  if ($oldEth -or $oldWifi) {
    $idx = $(if ($oldOwner) { Find-PhoneIndex $oldOwner } else { -1 })
    if ($idx -ge 0) {
      $p = $script:Phones[$idx]
      if (-not $p.Eth)  { $p.Eth  = $oldEth }
      if (-not $p.Wifi) { $p.Wifi = $oldWifi }
    } elseif ((Find-PhoneIndex '') -lt 0) {
      # Nobody answered: keep the IPs, the phone gets identified on its first connection
      $script:Phones.Add((New-Phone '' 'Phone' $oldEth $oldWifi))
    }
  }
  Write-Phones
  Remove-Item -Force $OldIpsFile
}

# ---- Which phone? ----
# Every saved phone, once each (a phone plugged in by USB is saved above, so it's
# in the list too, marked "USB"). Asked only when there's more than one.
if ($script:Phones.Count -eq 0) {
  Show-Error 'no phone found' ("Plug the phone in with a USB cable once (needed after every phone restart) " +
    "so PhoneConnect can turn on network mode. Make sure USB debugging is on and you tapped Allow on the phone.")
  exit 1
}

$script:ChosenId = $script:Phones[0].Id
if ($script:Phones.Count -gt 1) {
  $labels = @(); $defaultLabel = $null
  foreach ($p in $script:Phones) {
    $label = $(if ($p.Name) { $p.Name } else { 'Phone' })
    if (-not $p.Id) { $label += ' (saved by an older version)' }
    $same = @($script:Phones | Where-Object { $_.Name -eq $p.Name }).Count
    if ($same -gt 1 -and $p.Id) { $label += ' (...' + $p.Id.Substring([Math]::Max(0, $p.Id.Length - 4)) + ')' }
    $onUsb = $p.Id -and $usbOf.ContainsKey($p.Id)
    if ($onUsb) { $label += ' - USB' }
    if ($onUsb -and -not $defaultLabel) { $defaultLabel = $label }
    $labels += $label
  }
  if (-not $defaultLabel) { $defaultLabel = $labels[0] }
  $choice = Choose 'Which phone do you want to connect to?' $labels $defaultLabel
  if (-not $choice) { exit 0 }
  $script:ChosenId = $script:Phones[[array]::IndexOf($labels, $choice)].Id
}

# ---- Connect to it. Priority: 1. USB  2. Ethernet (dock)  3. Wi-Fi ----
if ($script:ChosenId -and $usbOf.ContainsKey($script:ChosenId)) {
  # ---- 1. USB ----
  $script:Serial = $usbOf[$script:ChosenId]
  $script:Link = 'USB'
} else {
  # ---- 2. Ethernet, 3. Wi-Fi ----
  foreach ($kind in @('eth', 'wifi')) {
    $idx = Find-PhoneIndex $script:ChosenId
    if ($idx -lt 0) { break }
    $ip = $(if ($kind -eq 'eth') { $script:Phones[$idx].Eth } else { $script:Phones[$idx].Wifi })
    if (-not $ip) { continue }
    Log "Trying $kind at $ip..."
    if ((Try-Connect $ip) -and (Claim-Connection $script:ChosenId $ip $kind)) {
      $script:Link = $(if ($kind -eq 'eth') { 'Ethernet' } else { 'Wi-Fi' })
      break
    }
  }

  # Fallback: the phone connected through Android's Wireless debugging (found automatically)
  if (-not $script:Serial) {
    foreach ($wd in (Get-Devices | Where-Object { $_.State -eq 'device' -and $_.Serial -match '_adb-tls-connect' })) {
      if (-not $script:ChosenId -or (Get-PhoneId $wd.Serial) -eq $script:ChosenId) {
        $script:Serial = $wd.Serial
        $script:Link = 'Wireless debugging'
        Learn-Phone $script:Serial $script:ChosenId
        $script:ChosenId = $script:LearnedId
        break
      }
    }
  }

  if (-not $script:Serial) {
    $name = Get-SavedName $script:ChosenId
    if (-not $name) { $name = 'the phone' }
    Show-Error "can't reach $name" ("Couldn't reach $name. Plug it in with a USB cable once (needed after every phone restart) " +
      "so PhoneConnect can turn on network mode. Make sure USB debugging is on and you tapped Allow on the phone.")
    exit 1
  }

  # The saved IPs were refreshed while connecting. This is also how the Ethernet IP
  # gets learned: it only exists while docked, and then there's no USB, so it's read over Wi-Fi.
  # Docked but we came in over Wi-Fi: switch this session to Ethernet
  $ethNow = $script:LearnedEth
  if ($ethNow -and $script:Link -ne 'Ethernet') {
    $prev = $script:Serial
    Log "Phone has Ethernet ($ethNow) - switching to it"
    if ((Try-Connect $ethNow) -and (Claim-Connection $script:ChosenId $ethNow 'eth')) { $script:Link = 'Ethernet' }
    else { $script:Serial = $prev; Log "Ethernet not reachable, staying on $($script:Link)" }
  }
}
Set-PhoneUsed $script:ChosenId
$PhoneName = Get-SavedName $script:ChosenId
if (-not $PhoneName) { $PhoneName = $script:LearnedName }
Log "Connection: $PhoneName - $($script:Link) ($($script:Serial))"
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
  Run-Scrcpy (@('-s', $Serial, "--display-id=$dexId") + $common + @('--video-bit-rate=8M', "--window-title=PhoneConnect - $PhoneName, DeX ($Link)") + $ExtraArgs)
} else {
  Log "Mirroring phone screen, audio: $choice"
  Run-Scrcpy (@('-s', $Serial) + $common + @('--max-size=1600', '--video-bit-rate=6M', "--window-title=PhoneConnect - $PhoneName ($Link)") + $ExtraArgs)
}
