# Builds the Windows app, checks it starts, packs the installer into
# dist\ParTake-Setup.exe, then installs it, starts the installed copy and
# uninstalls it. Run from the repository root on Windows; CI calls it from
# .github/workflows/ci.yml and release.yml.
#   pwsh windows/installer/build.ps1 [-Version 0.7.0]
# Without -Version the build never checks for updates (PARTAKE_VERSION unset).
param([string]$Version = '')
$ErrorActionPreference = 'Stop'

function Check($what) {
  if ($LASTEXITCODE -ne 0) { throw "$what failed with exit code $LASTEXITCODE" }
}

# A started app must still be running after $Seconds; a crash on startup fails.
function Assert-Starts($Exe, $Seconds = 20) {
  $p = Start-Process -FilePath $Exe -PassThru
  Start-Sleep -Seconds $Seconds
  if ($p.HasExited) { throw "$Exe exited with code $($p.ExitCode) within $Seconds s" }
  Stop-Process -Id $p.Id -Force
  Write-Host "$Exe ran for $Seconds s"
}

flutter pub get; Check 'flutter pub get'
$buildArgs = @('build', 'windows', '--release')
if ($Version) { $buildArgs += "--build-name=$Version", "--dart-define=PARTAKE_VERSION=$Version" }
flutter @buildArgs; Check 'flutter build windows'

$release = Join-Path $PWD 'build\windows\x64\runner\Release'
Assert-Starts (Join-Path $release 'partake.exe')

$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
  choco install innosetup -y --no-progress; Check 'choco install innosetup'
}
$appVersion = if ($Version) { $Version } else { '0.0.0' }
& $iscc "/DAppVersion=$appVersion" "/DBuildDir=$release" 'windows\installer\partake.iss'; Check 'ISCC'
$setup = Join-Path $PWD 'dist\ParTake-Setup.exe'
if (-not (Test-Path $setup)) { throw "$setup was not written" }

# The installer itself: silent per-user install, start, uninstall.
$p = Start-Process -FilePath $setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER' -PassThru -Wait
if ($p.ExitCode -ne 0) { throw "installer exited with code $($p.ExitCode)" }
$installed = Join-Path $env:LOCALAPPDATA 'Programs\ParTake'
Assert-Starts (Join-Path $installed 'partake.exe')
$shortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\ParTake\ParTake.lnk'
if (-not (Test-Path $shortcut)) { throw "Start menu shortcut missing: $shortcut" }
$p = Start-Process -FilePath (Join-Path $installed 'unins000.exe') -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES' -PassThru -Wait
if ($p.ExitCode -ne 0) { throw "uninstaller exited with code $($p.ExitCode)" }
Get-Item $setup | Format-List Name, Length
