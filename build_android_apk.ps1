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

Push-Location $projectRoot
try {
    Write-Host "==> Сборка Release APK (Pyure $appVersion)..." -ForegroundColor Cyan
    flutter pub get
    flutter build apk --release

    $builtApk = Join-Path $projectRoot "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path $builtApk)) {
        throw "Не найден файл сборки: $builtApk"
    }

    $distDir = Join-Path $projectRoot "dist"
    New-Item -ItemType Directory -Force -Path $distDir | Out-Null

    $targetApk = Join-Path $distDir "Pyure-$appVersion-android.apk"
    Copy-Item -Force $builtApk $targetApk
    Write-Host "`nГотово! APK: $targetApk" -ForegroundColor Green
} finally {
    Pop-Location
}
