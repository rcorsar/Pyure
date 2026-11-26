import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/database/app_database.dart';
import 'core/preferences/app_preferences.dart';
import 'features/library/presentation/library_provider.dart';
import 'features/player/data/system_media_bridge.dart';
import 'features/player/presentation/player_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }
  PaintingBinding.instance.imageCache
    ..maximumSize = 200
    ..maximumSizeBytes = 48 << 20;
  MediaKit.ensureInitialized();
  initDesktopDatabaseIfNeeded();

  final prefs = await SharedPreferences.getInstance();
  final mediaBridge = await AudioServiceMediaBridge.initialize();

  runApp(
    ProviderScope(
      overrides: [
        appPreferencesProvider.overrideWithValue(AppPreferences(prefs)),
        systemMediaBridgeProvider.overrideWithValue(mediaBridge),
      ],
      child: const PyureApp(),
    ),
  );
}
