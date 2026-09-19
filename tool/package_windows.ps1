#Requires -Version 5.1
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root
$Version = if ($args.Count -ge 1) { $args[0] } else { "1.0.0" }
$VenvPython = Join-Path $Root "engine\.venv\Scripts\python.exe"
$Dist = Join-Path $Root "dist"
$Release = Join-Path $Root "build\windows\x64\runner\Release"

Write-Host "==> Python engine (PyInstaller)"
if (-not (Test-Path $VenvPython)) {
  python -m venv (Join-Path $Root "engine\.venv")
}
& $VenvPython -m pip install -q --upgrade pip
& $VenvPython -m pip install -q -r (Join-Path $Root "engine\requirements.txt") pyinstaller
Remove-Item -Recurse -Force (Join-Path $Root "engine\build") -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $Root "engine\dist") -ErrorAction SilentlyContinue
& $VenvPython -m PyInstaller --noconfirm --clean `
  --workpath (Join-Path $Root "engine\build") `
  --distpath (Join-Path $Root "engine\dist") `
  (Join-Path $Root "installer\podpisun_engine.spec")

Write-Host "==> Flutter Windows release"
flutter build windows --release

if (-not (Test-Path $Release)) {
  throw "Release folder not found: $Release"
}

$EngineDest = Join-Path $Release "podpisun_engine"
if (Test-Path $EngineDest) { Remove-Item -Recurse -Force $EngineDest }
Copy-Item -Recurse (Join-Path $Root "engine\dist\podpisun_engine") $EngineDest

Write-Host "==> Stamp vault 250 MB next to the exe"
$Vault = Join-Path $Release "pechatky.podpisun"
$ImportArgs = @()
$PngDev = Join-Path $Root "portable_data\PNG"
if (Test-Path $PngDev) {
  $ImportArgs += @("--import-dir", $PngDev)
}
$PngRelease = Join-Path $Release "PNG"
if (Test-Path $PngRelease) {
  $ImportArgs += @("--import-dir", $PngRelease)
}
& dart run tool/init_stamp_vault.dart $Vault @ImportArgs
if (Test-Path $PngRelease) { Remove-Item -Recurse -Force $PngRelease }

New-Item -ItemType Directory -Force -Path $Dist | Out-Null

$Iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($Iscc) {
  Write-Host "==> Inno Setup (installer)"
  & $Iscc (Join-Path $Root "installer\windows\podpisun.iss")
  Write-Host "Done: $(Join-Path $Dist "Pidpysun-$Version-windows-setup.exe")"

  Write-Host "==> One-file portable (double-click to run)"
  & $Iscc (Join-Path $Root "installer\windows\podpisun_portable.iss")
  Write-Host "Done: $(Join-Path $Dist "Pidpysun-$Version-windows-portable.exe")"
} else {
  $Zip = Join-Path $Dist "Pidpysun-$Version-windows.zip"
  if (Test-Path $Zip) { Remove-Item $Zip }
  Compress-Archive -Path (Join-Path $Release "*") -DestinationPath $Zip
  Write-Host "Inno Setup not found. Zip created: $Zip"
  Write-Host "Install Inno Setup 6 and re-run this script to get setup.exe / portable.exe"
}
