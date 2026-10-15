# Builds PhoneConnect for Windows:
#   dist/PhoneConnect-Setup.exe                       installer (Intel/AMD and ARM PCs)
#   dist/PhoneConnect-Windows-x64-portable.zip        no-install version, Intel/AMD
#   dist/PhoneConnect-Windows-arm64-portable.zip      no-install version, ARM (e.g. Parallels on Apple Silicon)
#
# Run on Windows:   powershell -ExecutionPolicy Bypass -File build\build-windows.ps1
# Needs: Inno Setup 6 for the installer (https://jrsoftware.org/isdl.php, or
#        `choco install innosetup`). Use -SkipInstaller to build only the zips.
# The version stamped into the app comes from $env:APP_VERSION, e.g. 1.2.3
# (the GitHub workflow sets it). Without it, a local build is "<VERSION file>-dev".

param([switch]$SkipInstaller)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes downloads much faster in Windows PowerShell

$Root = Split-Path -Parent $PSScriptRoot
$Dl   = Join-Path $Root 'downloads'
$Dist = Join-Path $Root 'dist'
$Work = Join-Path $Dist 'windows'
$Stage = Join-Path $Work 'stage'

# ---- versions ----
$cfg = @{}
foreach ($line in Get-Content (Join-Path $Root 'build/versions.env')) {
  if ($line -match '^\s*([A-Z0-9_]+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2].Trim() }
}
$ScrcpyVersion = $cfg['SCRCPY_VERSION']
if ($env:APP_VERSION) { $Version = $env:APP_VERSION.Trim() }
else { $Version = (Get-Content (Join-Path $Root 'VERSION') -Raw).Trim() + '-dev' }
# Windows file versions need four plain numbers: 1.2.3 -> 1.2.3.0
$NumericVersion = ($Version -split '-')[0]
if ($NumericVersion -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 1.2.3 (got '$Version')" }
$FileVersion = "$NumericVersion.0"
Write-Host "Building PhoneConnect $Version for Windows (scrcpy $ScrcpyVersion)"

function Get-Verified([string]$name, [string]$sha) {
  New-Item -ItemType Directory -Force -Path $Dl | Out-Null
  $file = Join-Path $Dl $name
  if (-not (Test-Path $file) -or (Get-FileHash $file -Algorithm SHA256).Hash -ne $sha.ToUpper()) {
    Write-Host "Downloading $name"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/Genymobile/scrcpy/releases/download/v$ScrcpyVersion/$name" -OutFile $file
  }
  $got = (Get-FileHash $file -Algorithm SHA256).Hash
  if ($got -ne $sha.ToUpper()) { throw "Checksum mismatch for ${name}: got $got, expected $sha" }
  return $file
}

if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
foreach ($f in @('PhoneConnect-Setup.exe', 'PhoneConnect-Windows-x64-portable.zip', 'PhoneConnect-Windows-arm64-portable.zip')) {
  $p = Join-Path $Dist $f; if (Test-Path $p) { Remove-Item -Force $p }
}

# ---- bundled tools: scrcpy, adb and their DLLs, for Intel/AMD and ARM ----
$sets = @(
  @{ Arch = 'x64';   Zip = "scrcpy-win64-v$ScrcpyVersion.zip";    Sha = $cfg['SHA256_WIN64'] },
  @{ Arch = 'arm64'; Zip = "scrcpy-winarm64-v$ScrcpyVersion.zip"; Sha = $cfg['SHA256_WINARM64'] }
)
foreach ($s in $sets) {
  $zip = Get-Verified $s.Zip $s.Sha
  $tmp = Join-Path $Work ("unzip-" + $s.Arch)
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $src = Get-ChildItem $tmp -Directory | Select-Object -First 1
  $dest = Join-Path $Stage ("tools-" + $s.Arch)
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  # everything except scrcpy's own helper shortcuts and images
  Get-ChildItem $src.FullName -File |
    Where-Object { $_.Extension -notin @('.bat', '.vbs', '.png') } |
    Copy-Item -Destination $dest
  Rename-Item (Join-Path $dest 'LICENSE.txt') 'scrcpy-LICENSE.txt'
  Remove-Item -Recurse -Force $tmp
}

# ---- the script (saved with a BOM so Windows PowerShell reads it as UTF-8) ----
$ps1 = (Get-Content (Join-Path $Root 'windows/PhoneConnect.ps1') -Raw).Replace('@VERSION@', $Version)
[IO.File]::WriteAllText((Join-Path $Stage 'PhoneConnect.ps1'), $ps1, (New-Object Text.UTF8Encoding $true))
Copy-Item (Join-Path $Root 'assets/PhoneConnect.ico') $Stage
Copy-Item (Join-Path $Root 'THIRD_PARTY_NOTICES.md') $Stage
@"
PhoneConnect $Version
Mirror and control your Android phone from this PC (powered by scrcpy $ScrcpyVersion).

Start it from the Start menu or the desktop shortcut.
Phone setup, tips and troubleshooting: see the README on the project page.
Log of the last run: %TEMP%\PhoneConnect.log
"@ | Set-Content -Path (Join-Path $Stage 'README.txt') -Encoding ASCII

# ---- PhoneConnect.exe: small launcher with the icon (C# compiler that ships with Windows) ----
$csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe' }
if (-not (Test-Path $csc)) { throw "C# compiler not found (.NET Framework 4 is part of Windows 10/11)" }
# version info shown in the .exe's Properties -> Details
$versionCs = Join-Path $Work 'Version.cs'
@"
[assembly: System.Reflection.AssemblyVersion("$FileVersion")]
[assembly: System.Reflection.AssemblyFileVersion("$FileVersion")]
[assembly: System.Reflection.AssemblyInformationalVersion("$Version")]
[assembly: System.Reflection.AssemblyCopyright("PhoneConnect contributors")]
"@ | Set-Content -Path $versionCs -Encoding ASCII
& $csc /nologo /target:winexe /optimize+ /platform:anycpu `
  "/out:$(Join-Path $Stage 'PhoneConnect.exe')" `
  "/win32icon:$(Join-Path $Root 'assets/PhoneConnect.ico')" `
  /reference:System.Windows.Forms.dll `
  (Join-Path $Root 'windows/Launcher.cs') $versionCs
if ($LASTEXITCODE -ne 0) { throw "Compiling the launcher failed" }

# ---- portable zips ----
foreach ($arch in @('x64', 'arm64')) {
  $folder = Join-Path $Work "PhoneConnect-$arch/PhoneConnect"
  New-Item -ItemType Directory -Force -Path $folder | Out-Null
  foreach ($f in @('PhoneConnect.exe', 'PhoneConnect.ps1', 'PhoneConnect.ico', 'README.txt', 'THIRD_PARTY_NOTICES.md')) {
    Copy-Item (Join-Path $Stage $f) $folder
  }
  Copy-Item (Join-Path $Stage "tools-$arch") (Join-Path $folder 'tools') -Recurse
  Compress-Archive -Path $folder -DestinationPath (Join-Path $Dist "PhoneConnect-Windows-$arch-portable.zip")
}

# ---- installer ----
if (-not $SkipInstaller) {
  $iscc = (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source
  if (-not $iscc) {
    foreach ($c in @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe")) {
      if (Test-Path $c) { $iscc = $c; break }
    }
  }
  if (-not $iscc) { throw "Inno Setup 6 not found. Install it (choco install innosetup) or run with -SkipInstaller." }
  & $iscc /Q "/DAppVersion=$Version" "/DFileVersion=$FileVersion" "/DStage=$Stage" "/DOutDir=$Dist" (Join-Path $Root 'windows/installer.iss')
  if ($LASTEXITCODE -ne 0) { throw "Building the installer failed" }
}

Write-Host "Done (version $Version):"
Get-ChildItem $Dist -File | ForEach-Object { Write-Host ("  {0}  ({1:N1} MB)" -f $_.Name, ($_.Length / 1MB)) }
