#Requires -Version 5.1
$ErrorActionPreference = "Stop"

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
  throw "Не знайдено $Release"
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
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($Iscc) {
  Write-Host "==> Inno Setup"
  & $Iscc (Join-Path $Root "installer\windows\podpisun.iss")
  Write-Host "Готово: $(Join-Path $Dist "Pidpysun-$Version-windows-setup.exe")"
} else {
  $Zip = Join-Path $Dist "Pidpysun-$Version-windows.zip"
  if (Test-Path $Zip) { Remove-Item $Zip }
  Compress-Archive -Path (Join-Path $Release "*") -DestinationPath $Zip
  Write-Host "Inno Setup не знайдено. Зібрано zip: $Zip"
  Write-Host "Встановіть Inno Setup 6 і запустіть скрипт знову, щоб отримати setup.exe"
}

Write-Host "==> Portable folder"
$Portable = Join-Path $Dist "Pidpysun-$Version-windows-portable"
$PortableZip = Join-Path $Dist "Pidpysun-$Version-windows-portable.zip"
if (Test-Path $Portable) { Remove-Item -Recurse -Force $Portable }
if (Test-Path $PortableZip) { Remove-Item $PortableZip }
Copy-Item -Recurse (Join-Path $Release "*") $Portable
@"
Підписун — портативна версія

Скопіюйте всю цю теку (не лише podpisun.exe) на флешку.
Усі печатки лежать у одному файлі pechatky.podpisun (250 МБ) поруч із exe.

Якщо на іншому комп’ютері Підписун уже стоїть — достатньо скопіювати
лише pechatky.podpisun і покласти його поруч із podpisun.exe.

Додавайте PNG кнопкою «Додати PNG» або перетягуванням у ліву панель.
"@ | Set-Content -Encoding UTF8 (Join-Path $Portable "ЧИТАЙМЕНЕ.txt")
Compress-Archive -Path $Portable -DestinationPath $PortableZip
Write-Host "Готово: $Portable"
Write-Host "Архів:  $PortableZip"
