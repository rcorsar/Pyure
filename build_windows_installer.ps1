$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$pubspecPath = Join-Path $projectRoot "pubspec.yaml"
$pubspecText = Get-Content -Raw -Encoding UTF8 $pubspecPath

$appVersion = "0.1.0"
if ($pubspecText -match "(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)") {
    $appVersion = $Matches[1]
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter SDK не найден в PATH."
}

$isccCandidates = @(
    (Get-Command "ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
) | Where-Object { $_ -and (Test-Path $_) }

$isccPath = $isccCandidates | Select-Object -First 1
if (-not $isccPath) {
    Write-Error "Inno Setup 6 (ISCC.exe) не найден. Установите его командой: winget install JRSoftware.InnoSetup"
}

Push-Location $projectRoot
try {
    Write-Host "==> Сборка Release для Windows (Pyure $appVersion)..." -ForegroundColor Cyan
    flutter pub get
    flutter build windows --release

    $distDir = Join-Path $projectRoot "dist"
    New-Item -ItemType Directory -Force -Path $distDir | Out-Null

    Write-Host "==> Упаковка установщика Inno Setup..." -ForegroundColor Cyan
    & $isccPath "/DMyAppVersion=$appVersion" (Join-Path $projectRoot "installer\pyure.iss")
    if ($LASTEXITCODE -ne 0) {
        throw "ISCC.exe завершился с кодом $LASTEXITCODE"
    }

    $setupExe = Join-Path $distDir "Pyure-$appVersion-windows-x64-setup.exe"
    Write-Host "`nГотово! Установщик: $setupExe" -ForegroundColor Green
} finally {
    Pop-Location
}
