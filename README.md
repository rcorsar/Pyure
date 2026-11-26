# Pyure

Локальный офлайн MP3-плеер для Windows и Android (в том числе GrapheneOS).
Работает только с вашей папкой на устройстве — без сети, рекламы и лишних разрешений.

## Что умеет

- Сканирует выбранную папку и подпапки с MP3, сохраняет библиотеку в локальный кэш.
- Читает ID3-теги и обложки (встроенные в файл или `cover.jpg` / `folder.jpg` рядом). Если теги пустые, берёт исполнителя и название из имени файла (`Исполнитель - Трек`), а альбом — из имени папки.
- Сортирует альбомы по исполнителю и названию (сначала латиница A–Z, затем кириллица А–Я) и треки по названию, альбому или дате добавления.
- Мгновенно ищет по трекам, исполнителям и альбомам, помнит последний трек, позицию и громкость.
- Работает в фоне на Android и управляется с гарнитуры, шторки уведомлений и кнопок Windows.
- На Android открывает музыку через системный Storage Access Framework (SAF): не запрашивает доступ ко всей памяти устройства, а в релизном APK вырезано разрешение `INTERNET`.

## Установка

Готовые сборки лежат на странице [Releases](https://github.com/rcorsar/Pyure/releases):

- **Windows (x64)**: скачайте `Pyure-<версия>-windows-x64-setup.exe` и запустите установку.
- **Android / GrapheneOS**: скачайте `Pyure-<версия>-android.apk` и установите APK, после первого запуска выберите папку с музыкой.

## Сборка из исходников

Нужен Flutter SDK (`>= 3.44.0`). Для сборки Windows — Visual Studio Build Tools (C++), для установщика — Inno Setup 6. Для Android — JDK 17 и Android SDK.

Windows (собрать и сразу поставить в `%LOCALAPPDATA%\Programs\Pyure` с ярлыками):

```powershell
powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
```

Windows-установщик `.exe` в папку `dist/`:

```powershell
powershell -ExecutionPolicy Bypass -File .\build_windows_installer.ps1
```

Android `.apk` в папку `dist/`:

```powershell
powershell -ExecutionPolicy Bypass -File .\build_android_apk.ps1
```
