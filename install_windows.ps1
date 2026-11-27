$ErrorActionPreference = "Stop"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter SDK не найден в PATH."
}

$projectRoot = $PSScriptRoot
$installDir = Join-Path $env:LOCALAPPDATA "Programs\Pyure"
$releaseDir = Join-Path $projectRoot "build\windows\x64\runner\Release"
$exePath = Join-Path $installDir "pyure.exe"
$startMenuShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Pyure.lnk"
$desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Pyure.lnk"

Push-Location $projectRoot
try {
    Write-Host "==> Получение зависимостей и сборка Release .exe..." -ForegroundColor Cyan
    flutter pub get
    flutter build windows --release
} finally {
    Pop-Location
}

if (-not (Test-Path (Join-Path $releaseDir "pyure.exe"))) {
    Write-Error "Не найден собранный файл $releaseDir\pyure.exe"
}

Write-Host "==> Остановка запущенного процесса Pyure (если открыт)..." -ForegroundColor Cyan
Get-Process -Name "pyure" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

Write-Host "==> Установка программы в $installDir..." -ForegroundColor Cyan
if (Test-Path $installDir) {
    Get-ChildItem -Force $installDir | Where-Object { $_.Name -notlike "unins*" } | Remove-Item -Recurse -Force
} else {
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
}
Copy-Item -Recurse -Force (Join-Path $releaseDir "*") $installDir

Write-Host "==> Создание ярлыков в меню Пуск и на Рабочем столе..." -ForegroundColor Cyan
$wsShell = New-Object -ComObject WScript.Shell

foreach ($lnkPath in @($startMenuShortcut, $desktopShortcut)) {
    $shortcut = $wsShell.CreateShortcut($lnkPath)
    $shortcut.TargetPath = $exePath
    $shortcut.WorkingDirectory = $installDir
    $shortcut.IconLocation = "$exePath,0"
    $shortcut.Description = "Pyure — offline MP3 player"
    $shortcut.Save()
}

Write-Host "`nГотово! Pyure установлен как программа Windows:" -ForegroundColor Green
Write-Host "  EXE:        $exePath"
Write-Host "  Меню Пуск:  $startMenuShortcut"
Write-Host "  Раб. стол:  $desktopShortcut"
Write-Host "`nТеперь найдите 'Pyure' в поиске меню Пуск -> ПКМ -> Закрепить на начальном экране / панели задач." -ForegroundColor Yellow
