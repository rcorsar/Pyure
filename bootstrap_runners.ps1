$ErrorActionPreference = "Stop"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter SDK не найден в PATH. Сначала установите Flutter и добавьте <flutter>\bin в PATH."
}

$projectRoot = $PSScriptRoot
$tmpDir = Join-Path $env:TEMP ("pyure_tpl_" + [Guid]::NewGuid().ToString("N").Substring(0, 8))

try {
    Write-Host "==> Генерация шаблона нативных раннеров (Windows + Android)..." -ForegroundColor Cyan
    flutter create --org com.pyure --project-name pyure --platforms=windows,android $tmpDir

    foreach ($platformDir in @("windows", "android")) {
        $src = Join-Path $tmpDir $platformDir
        $dst = Join-Path $projectRoot $platformDir
        if (Test-Path $dst) {
            Remove-Item -Recurse -Force $dst
        }
        Copy-Item -Recurse -Force $src $dst
    }

    Write-Host "==> Настройка Android package ID (com.pyure.player) и манифеста..." -ForegroundColor Cyan
    foreach ($gradleFile in @(
        (Join-Path $projectRoot "android\app\build.gradle.kts"),
        (Join-Path $projectRoot "android\app\build.gradle")
    )) {
        if (Test-Path $gradleFile) {
            $content = Get-Content -Raw -Encoding UTF8 $gradleFile
            $updated = $content.Replace("com.pyure.pyure", "com.pyure.player")
            Set-Content -Path $gradleFile -Value $updated -Encoding UTF8
        }
    }

    Copy-Item -Force `
        (Join-Path $projectRoot "android_config\AndroidManifest.xml") `
        (Join-Path $projectRoot "android\app\src\main\AndroidManifest.xml")

    $releaseManifestSrc = Join-Path $projectRoot "android_config\release\AndroidManifest.xml"
    if (Test-Path $releaseManifestSrc) {
        $releaseManifestDir = Join-Path $projectRoot "android\app\src\release"
        New-Item -ItemType Directory -Force -Path $releaseManifestDir | Out-Null
        Copy-Item -Force $releaseManifestSrc (Join-Path $releaseManifestDir "AndroidManifest.xml")
    }

    $customRes = Join-Path $projectRoot "android_config\res"
    if (Test-Path $customRes) {
        Copy-Item -Recurse -Force `
            (Join-Path $customRes "*") `
            (Join-Path $projectRoot "android\app\src\main\res")
    }

    $oldKotlinDir = Join-Path $projectRoot "android\app\src\main\kotlin\com\pyure\pyure"
    if (Test-Path $oldKotlinDir) {
        Remove-Item -Recurse -Force $oldKotlinDir
    }
    $newKotlinDir = Join-Path $projectRoot "android\app\src\main\kotlin\com\pyure\player"
    New-Item -ItemType Directory -Force -Path $newKotlinDir | Out-Null
    Copy-Item -Force `
        (Join-Path $projectRoot "android_config\MainActivity.kt") `
        (Join-Path $newKotlinDir "MainActivity.kt")

    $winMainCpp = Join-Path $projectRoot "windows\runner\main.cpp"
    if (Test-Path $winMainCpp) {
        $cpp = Get-Content -Raw -Encoding UTF8 $winMainCpp
        $cpp = $cpp.Replace('L"pyure"', 'L"Pyure"')
        Set-Content -Path $winMainCpp -Value $cpp -Encoding UTF8
    }

    $winRc = Join-Path $projectRoot "windows\runner\Runner.rc"
    if (Test-Path $winRc) {
        $rc = Get-Content -Raw -Encoding UTF8 $winRc
        $rc = $rc.Replace('"FileDescription", "pyure"', '"FileDescription", "Pyure"')
        $rc = $rc.Replace('"InternalName", "pyure"', '"InternalName", "Pyure"')
        $rc = $rc.Replace('"ProductName", "pyure"', '"ProductName", "Pyure"')
        Set-Content -Path $winRc -Value $rc -Encoding UTF8
    }

    $winCmake = Join-Path $projectRoot "windows\CMakeLists.txt"
    if (Test-Path $winCmake) {
        $cmake = Get-Content -Raw -Encoding UTF8 $winCmake
        $marker = "include(flutter/generated_plugins.cmake)"
        if ($cmake.Contains($marker) -and -not $cmake.Contains("_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS")) {
            $patch = $marker + "`n`nif(TARGET audio_service_win_plugin)`n  target_compile_definitions(audio_service_win_plugin PRIVATE _SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)`nendif()"
            $cmake = $cmake.Replace($marker, $patch)
            Set-Content -Path $winCmake -Value $cmake -Encoding UTF8
        }
    }

    Push-Location $projectRoot
    try {
        Write-Host "==> Установка зависимостей (flutter pub get)..." -ForegroundColor Cyan
        flutter pub get

        Write-Host "==> Проверка анализатора (flutter analyze)..." -ForegroundColor Cyan
        flutter analyze

        Write-Host "==> Запуск тестов (flutter test)..." -ForegroundColor Cyan
        flutter test
    } finally {
        Pop-Location
    }

    Write-Host "`nГотово! Для запуска на Windows 11 выполните: flutter run -d windows" -ForegroundColor Green
} finally {
    if (Test-Path $tmpDir) {
        Remove-Item -Recurse -Force $tmpDir
    }
}
