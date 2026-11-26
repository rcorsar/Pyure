# Пюре (`pyure`)

Бесплатный open-source офлайн MP3-плеер для **Windows 11** и **Android (GrapheneOS)**.

## Что нужно установить на чистой Windows 11

1. **Flutter SDK** (Windows zip со страницы [docs.flutter.dev/get-started/install/windows/windows](https://docs.flutter.dev/get-started/install/windows/windows)):
   - Распакуйте в `C:\src\flutter` (путь без кириллицы и пробелов).
   - Добавьте `C:\src\flutter\bin` в переменную среды `Path`.
2. **Visual Studio 2022 Community** (или **Visual Studio Build Tools 2022**):
   - Обязательно отметьте рабочую нагрузку **Desktop development with C++** (*Разработка классических приложений на C++*).
   - Проверьте окружение командой: `flutter doctor -v` (в пункте *Visual Studio* не должно быть ошибок).
3. *(Только для последующей сборки `.apk` под Pixel 10 / GrapheneOS)*: **Android Studio** + Android SDK и `flutter doctor --android-licenses`.

## Первый запуск на Windows 11

Откройте PowerShell в папке проекта `r:\Desktop\Lagring2\Antigravity\pyure` и выполните:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\bootstrap_runners.ps1
flutter run -d windows
```

Скрипт [bootstrap_runners.ps1](bootstrap_runners.ps1) сгенерирует актуальные папки `windows/` и `android/`, пропишет `com.pyure.player`, применит `AndroidManifest.xml` и `MainActivity.kt` из `android_config/`, скачает зависимости и прогонит `flutter analyze` + `flutter test`.

## Сборка и установка как программы на Windows 11

Чтобы собрать release `.exe`, установить его в `%LOCALAPPDATA%\Programs\Pyure` и создать ярлыки в **меню Пуск** и на **Рабочем столе** (чтобы можно было закрепить в Пуске и на панели задач):

```powershell
powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
```

## Сборка `.apk` для Android / GrapheneOS

```powershell
flutter build apk --release
```
