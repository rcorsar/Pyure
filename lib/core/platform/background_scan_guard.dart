import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Управляет нативным сервисом защиты фонового сканирования (Android
/// Foreground Service с типом `dataSync` и `PARTIAL_WAKE_LOCK`), чтобы
/// индексация медиатеки не останавливалась при сворачивании приложения.
abstract interface class BackgroundScanGuard {
  Future<void> startScan({required String folderName});

  Future<void> updateProgress({
    required int processed,
    required int total,
    required String fileName,
  });

  Future<void> stopScan();
}

BackgroundScanGuard createBackgroundScanGuard() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return AndroidBackgroundScanGuard();
  }
  return const NoopBackgroundScanGuard();
}

class NoopBackgroundScanGuard implements BackgroundScanGuard {
  const NoopBackgroundScanGuard();

  @override
  Future<void> startScan({required String folderName}) async {}

  @override
  Future<void> updateProgress({
    required int processed,
    required int total,
    required String fileName,
  }) async {}

  @override
  Future<void> stopScan() async {}
}

class AndroidBackgroundScanGuard implements BackgroundScanGuard {
  AndroidBackgroundScanGuard({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.pyure.player/background_scan',
  );

  final MethodChannel _channel;
  bool _isActive = false;

  Future<void> _invokeSafe(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Игнорируем в тестах без нативного плагина.
    } on PlatformException {
      // Не блокируем сканирование, если ОС ограничила foreground-сервис.
    }
  }

  @override
  Future<void> startScan({required String folderName}) async {
    _isActive = true;
    await _invokeSafe('startScan', <String, Object?>{'folderName': folderName});
  }

  @override
  Future<void> updateProgress({
    required int processed,
    required int total,
    required String fileName,
  }) async {
    if (!_isActive) return;
    await _invokeSafe('updateScanProgress', <String, Object?>{
      'processed': processed,
      'total': total,
      'fileName': fileName,
    });
  }

  @override
  Future<void> stopScan() async {
    _isActive = false;
    await _invokeSafe('stopScan');
  }
}
