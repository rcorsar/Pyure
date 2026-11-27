import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pyure/app/app.dart';
import 'package:pyure/app/theme/pyure_theme.dart';
import 'package:pyure/core/database/app_database.dart';
import 'package:pyure/core/models/album.dart';
import 'package:pyure/core/models/album_sort_order.dart';
import 'package:pyure/core/models/track.dart';
import 'package:pyure/core/models/track_sort_order.dart';
import 'package:pyure/core/platform/background_scan_guard.dart';
import 'package:pyure/core/platform/music_source.dart';
import 'package:pyure/core/preferences/app_preferences.dart';
import 'package:pyure/core/utils/formatters.dart';
import 'package:pyure/features/library/data/library_scanner_service.dart';
import 'package:pyure/features/library/data/metadata_fallback_resolver.dart';
import 'package:pyure/features/library/presentation/library_provider.dart';
import 'package:pyure/features/library/presentation/widgets/artwork_box.dart';
import 'package:pyure/features/player/data/audio_playback_backend.dart';
import 'package:pyure/features/player/data/system_media_bridge.dart';
import 'package:pyure/features/player/presentation/now_playing_sheet.dart';
import 'package:pyure/features/player/presentation/player_provider.dart';

class _FakeAppDatabase implements AppDatabase {
  _FakeAppDatabase(this.tracks);

  final List<Track> tracks;

  @override
  String? get overridePath => null;

  @override
  Future<void> close() async {}

  @override
  Future<Track?> findTrackByIdOrUri({int? id, String? sourceUri}) async {
    for (final t in tracks) {
      if ((id != null && t.id == id) ||
          (sourceUri != null && t.sourceUri == sourceUri)) {
        return t;
      }
    }
    return null;
  }

  @override
  Future<List<Track>> getAllTracks({
    TrackSortOrder sortOrder = TrackSortOrder.title,
  }) async {
    final copy = List<Track>.from(tracks);
    switch (sortOrder) {
      case TrackSortOrder.title:
        copy.sort((a, b) => a.title.compareTo(b.title));
      case TrackSortOrder.album:
        copy.sort((a, b) => a.album.compareTo(b.album));
      case TrackSortOrder.addedAt:
        copy.sort((a, b) => b.addedAtEpochMs.compareTo(a.addedAtEpochMs));
    }
    return copy;
  }

  @override
  Future<Map<String, ExistingTrackRecord>> getExistingTrackIndex() async =>
      const {};

  @override
  Future<List<Track>> getTracksByAlbum(String albumKey) async =>
      tracks.where((t) => t.albumKey == albumKey).toList(growable: false);

  @override
  Future<List<Track>> searchTracks(String query) async {
    final q = query.trim().toLowerCase();
    return tracks
        .where(
          (t) =>
              t.title.toLowerCase().contains(q) ||
              t.artist.toLowerCase().contains(q) ||
              t.album.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  @override
  Future<void> syncFolderTracks({
    required String folderUri,
    required List<Track> updatedOrNewTracks,
    required Set<String> activeSourceUris,
  }) async {}
}

class _FakeMusicStorageSource implements MusicStorageSource {
  @override
  Future<bool> hasPersistedAccess(MusicFolderRef folder) async => true;

  @override
  Future<List<ScannedAudioEntry>> listMp3Entries(
    MusicFolderRef folder,
  ) async => const [];

  @override
  Future<MusicFolderRef?> pickMusicFolder() async => null;

  @override
  Future<Uint8List?> readBytes(String sourceUri) async => null;

  @override
  Future<String> resolvePlayableSource(String sourceUri) async => sourceUri;

  @override
  Future<T> withReadableFile<T>(
    String sourceUri,
    Future<T> Function(File file) action,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<T> withMetadataFile<T>(
    ScannedAudioEntry entry,
    Future<T> Function(File file, int fullFileSizeBytes) action,
  ) {
    throw UnimplementedError();
  }
}

class _FakePlaybackBackend implements AudioPlaybackBackend {
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _completed = StreamController<bool>.broadcast();

  bool currentPlaying = false;
  int playCalls = 0;
  int pauseCalls = 0;
  final List<(String source, bool play)> openCalls = [];

  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration> get durationStream => _duration.stream;
  @override
  Stream<bool> get completedStream => _completed.stream;

  void _setPlaying(bool value) {
    currentPlaying = value;
    _playing.add(value);
  }

  @override
  Future<void> open(String source, {required bool play}) async {
    openCalls.add((source, play));
    _setPlaying(play);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    _setPlaying(false);
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    _setPlaying(true);
  }

  @override
  Future<void> playOrPause() async {
    if (currentPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration position) async => _position.add(position);

  @override
  Future<void> setVolume(double volumeZeroToOne) async {}

  @override
  Future<void> dispose() async {
    await _playing.close();
    await _position.close();
    await _duration.close();
    await _completed.close();
  }
}

void main() {
  group('MetadataFallbackResolver', () {
    test('разбирает "Исполнитель - Трек" и корень папки как "Без альбома"', () {
      const entry = ScannedAudioEntry(
        sourceUri: r'C:\Music\Кино - Группа крови.mp3',
        fileName: 'Кино - Группа крови.mp3',
        parentFolderName: '',
        isRootLevel: true,
        sizeBytes: 1024,
        modifiedMs: 1000,
      );

      final resolved = MetadataFallbackResolver.resolve(entry: entry);
      expect(resolved.artist, 'Кино');
      expect(resolved.title, 'Группа крови');
      expect(resolved.album, 'Без альбома');
      expect(resolved.albumKey, MetadataFallbackResolver.noAlbumKey);
    });

    test('использует имя родительской папки, если тег Album отсутствует', () {
      const entry = ScannedAudioEntry(
        sourceUri: r'C:\Music\Звезда по имени Солнце\01. Пачка сигарет.mp3',
        fileName: '01. Пачка сигарет.mp3',
        parentFolderName: 'Звезда по имени Солнце',
        isRootLevel: false,
        sizeBytes: 2048,
        modifiedMs: 2000,
      );

      final resolved = MetadataFallbackResolver.resolve(
        entry: entry,
        tagTitle: 'Пачка сигарет',
        tagArtist: 'Кино',
      );
      expect(resolved.title, 'Пачка сигарет');
      expect(resolved.artist, 'Кино');
      expect(resolved.album, 'Звезда по имени Солнце');
    });
  });

  group('Formatters и PlaybackRepeatMode', () {
    test('корректно склоняет счётчик треков', () {
      expect(formatTrackCount(1), '1 трек');
      expect(formatTrackCount(2), '2 трека');
      expect(formatTrackCount(5), '5 треков');
      expect(formatTrackCount(11), '11 треков');
      expect(formatTrackCount(21), '21 трек');
    });

    test('форматирует длительность', () {
      expect(formatDurationMs(65000), '1:05');
      expect(formatDurationMs(3661000), '1:01:01');
    });

    test('переключает режимы повтора по кругу', () {
      expect(PlaybackRepeatMode.off.next(), PlaybackRepeatMode.all);
      expect(PlaybackRepeatMode.all.next(), PlaybackRepeatMode.one);
      expect(PlaybackRepeatMode.one.next(), PlaybackRepeatMode.off);
    });

    test('сортирует латиницу A–Z раньше кириллицы А–Я (включая Ё)', () {
      final items = ['50 Cent', 'Агата', 'Zebra', 'Ёжик', 'AC/DC', 'Ель', 'Жук']
        ..sort(compareLatinThenCyrillic);
      expect(items, [
        'AC/DC',
        'Zebra',
        'Агата',
        'Ель',
        'Ёжик',
        'Жук',
        '50 Cent',
      ]);
    });

    test('сортирует альбомы по исполнителю и по названию (EN -> RU)', () {
      const albums = [
        Album(
          key: '1',
          title: 'Яблоко',
          artist: 'Linkin Park',
          trackCount: 3,
          folderUri: 'f',
        ),
        Album(
          key: '2',
          title: 'Alpha',
          artist: 'Кино',
          trackCount: 5,
          folderUri: 'f',
        ),
        Album(
          key: '3',
          title: 'Белый день',
          artist: 'Агата Кристи',
          trackCount: 2,
          folderUri: 'f',
        ),
      ];

      final byArtist = MetadataFallbackResolver.sortAlbums(
        albums,
        AlbumSortOrder.artist,
      );
      expect(byArtist.map((a) => a.artist), [
        'Linkin Park',
        'Агата Кристи',
        'Кино',
      ]);

      final byTitle = MetadataFallbackResolver.sortAlbums(
        albums,
        AlbumSortOrder.title,
      );
      expect(byTitle.map((a) => a.title), [
        'Alpha',
        'Белый день',
        'Яблоко',
      ]);
    });
  });

  testWidgets('Переключение сортировки альбомов и запуск трека из списка', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    const sampleTracks = [
      Track(
        id: 1,
        title: 'Спокойная ночь',
        artist: 'Кино',
        album: 'Alpha',
        albumKey: 'album:alpha',
        sourceUri: 'sample://1.mp3',
        folderUri: 'sample://root',
        parentFolderName: 'Alpha',
        durationMs: 360000,
        addedAtEpochMs: 1000,
        fileSizeBytes: 5000,
        lastModifiedMs: 1000,
      ),
      Track(
        id: 2,
        title: 'Numb',
        artist: 'Linkin Park',
        album: 'Яблоко',
        albumKey: 'album:яблоко',
        sourceUri: 'sample://2.mp3',
        folderUri: 'sample://root',
        parentFolderName: 'Яблоко',
        durationMs: 185000,
        addedAtEpochMs: 2000,
        fileSizeBytes: 4000,
        lastModifiedMs: 1000,
      ),
    ];

    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferencesProvider.overrideWithValue(AppPreferences(prefs)),
          appDatabaseProvider.overrideWithValue(_FakeAppDatabase(sampleTracks)),
          musicStorageSourceProvider.overrideWithValue(_FakeMusicStorageSource()),
          audioPlaybackBackendProvider.overrideWithValue(_FakePlaybackBackend()),
          systemMediaBridgeProvider.overrideWithValue(NoopSystemMediaBridge()),
        ],
        child: const PyureApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('По исполнителю'), findsOneWidget);
    expect(find.text('По названию'), findsOneWidget);

    // По умолчанию сортировка по исполнителю: Linkin Park («Яблоко») слева от Кино («Alpha»).
    expect(
      tester.getTopLeft(find.text('Яблоко')).dx,
      lessThan(tester.getTopLeft(find.text('Alpha')).dx),
    );

    await tester.tap(find.text('По названию'));
    await tester.pumpAndSettle();

    // После переключения по названию: «Alpha» слева от «Яблоко».
    expect(
      tester.getTopLeft(find.text('Alpha')).dx,
      lessThan(tester.getTopLeft(find.text('Яблоко')).dx),
    );

    // Открытие альбома и выход назад по клавише Escape.
    await tester.tap(find.text('Яблоко'));
    await tester.pumpAndSettle();
    expect(find.text('Numb'), findsOneWidget);
    expect(find.text('Перемешать'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('По исполнителю'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Треки'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Перемешать'), findsNothing);
    expect(find.text('Спокойная ночь'), findsOneWidget);
    await tester.tap(find.text('Спокойная ночь'));
    await tester.pumpAndSettle();

    expect(find.text('Спокойная ночь'), findsWidgets);

    // Открываем полноэкранный плеер по тапу на мини-плеер и переходим на альбом.
    await tester.tap(find.text('Спокойная ночь').last);
    await tester.pumpAndSettle();
    expect(find.text('СЕЙЧАС ИГРАЕТ'), findsOneWidget);
    expect(find.byTooltip('На альбом'), findsOneWidget);

    await tester.tap(find.byTooltip('На альбом'));
    await tester.pumpAndSettle();
    expect(find.text('СЕЙЧАС ИГРАЕТ'), findsNothing);
    expect(find.text('Слушать'), findsOneWidget);
    expect(find.text('Alpha'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Слушать'), findsNothing);

    // На мобильном устройстве системный возврат с вкладки «Треки» возвращает на «Альбомы».
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Альбомы'), findsWidgets);
    expect(find.text('По исполнителю'), findsOneWidget);
  });

  testWidgets('Десктопная раскладка показывает Pyure и боковую панель', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferencesProvider.overrideWithValue(AppPreferences(prefs)),
          appDatabaseProvider.overrideWithValue(_FakeAppDatabase(const [])),
          musicStorageSourceProvider.overrideWithValue(_FakeMusicStorageSource()),
          audioPlaybackBackendProvider.overrideWithValue(_FakePlaybackBackend()),
          systemMediaBridgeProvider.overrideWithValue(NoopSystemMediaBridge()),
        ],
        child: const PyureApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Pyure'), findsOneWidget);
  });

  testWidgets('На мобильном экране альбомы идут по 3 в ряд без счётчика треков', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final fourAlbumTracks = [
      for (var i = 1; i <= 4; i++)
        Track(
          id: i,
          title: 'Track $i',
          artist: 'Artist A',
          album: 'Album $i',
          albumKey: 'album:$i',
          sourceUri: 'sample://album_$i.mp3',
          folderUri: 'sample://root',
          parentFolderName: 'Album $i',
          durationMs: 180000,
          addedAtEpochMs: 1000 + i,
          fileSizeBytes: 3000,
          lastModifiedMs: 1000,
        ),
    ];

    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferencesProvider.overrideWithValue(AppPreferences(prefs)),
          appDatabaseProvider.overrideWithValue(
            _FakeAppDatabase(fourAlbumTracks),
          ),
          musicStorageSourceProvider.overrideWithValue(
            _FakeMusicStorageSource(),
          ),
          audioPlaybackBackendProvider.overrideWithValue(
            _FakePlaybackBackend(),
          ),
          systemMediaBridgeProvider.overrideWithValue(NoopSystemMediaBridge()),
        ],
        child: const PyureApp(),
      ),
    );
    await tester.pumpAndSettle();

    final y1 = tester.getTopLeft(find.text('Album 1')).dy;
    final y3 = tester.getTopLeft(find.text('Album 3')).dy;
    final y4 = tester.getTopLeft(find.text('Album 4')).dy;

    expect(y3, equals(y1));
    expect(y4, greaterThan(y1));
    expect(find.text('1 трек'), findsNothing);
  });

  testWidgets(
    'Кнопка паузы в NowPlayingSheet показывает паузу сразу после старта трека и срабатывает с первого нажатия',
    (tester) async {
      final sampleTracks = [
        const Track(
          id: 1,
          title: 'Numb',
          artist: 'Linkin Park',
          album: 'Meteora',
          albumKey: 'lp:meteora',
          sourceUri: 'sample://lp_numb.mp3',
          folderUri: 'sample://root',
          parentFolderName: 'Meteora',
          durationMs: 185000,
          addedAtEpochMs: 1000,
          fileSizeBytes: 5000,
          lastModifiedMs: 1000,
        ),
        const Track(
          id: 2,
          title: 'Faint',
          artist: 'Linkin Park',
          album: 'Meteora',
          albumKey: 'lp:meteora',
          sourceUri: 'sample://lp_faint.mp3',
          folderUri: 'sample://root',
          parentFolderName: 'Meteora',
          durationMs: 162000,
          addedAtEpochMs: 1001,
          fileSizeBytes: 4800,
          lastModifiedMs: 1001,
        ),
      ];

      // Восстанавливаем прошлый трек (при старте open(..., play: false)).
      SharedPreferences.setMockInitialValues({
        'last_track_id': 2,
        'last_track_uri': 'sample://lp_faint.mp3',
      });
      final prefs = await SharedPreferences.getInstance();
      final fakeBackend = _FakePlaybackBackend();
      addTearDown(fakeBackend.dispose);

      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferencesProvider.overrideWithValue(AppPreferences(prefs)),
            appDatabaseProvider.overrideWithValue(
              _FakeAppDatabase(sampleTracks),
            ),
            musicStorageSourceProvider.overrideWithValue(
              _FakeMusicStorageSource(),
            ),
            audioPlaybackBackendProvider.overrideWithValue(fakeBackend),
            systemMediaBridgeProvider.overrideWithValue(
              NoopSystemMediaBridge(),
            ),
          ],
          child: const PyureApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Заходим в альбом и включаем первый трек.
      await tester.tap(find.text('Meteora'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Numb'));
      await tester.pumpAndSettle();

      // Открываем экран трека (NowPlayingSheet) по тапу на мини-плеер.
      await tester.tap(find.text('Numb').last);
      await tester.pumpAndSettle();
      expect(find.text('СЕЙЧАС ИГРАЕТ'), findsOneWidget);

      // Кнопка сразу должна показывать "Пауза", а не "Воспроизвести".
      final pauseBtnInSheet = find.descendant(
        of: find.byType(NowPlayingSheet),
        matching: find.byTooltip('Пауза'),
      );
      expect(pauseBtnInSheet, findsOneWidget);

      final pauseBefore = fakeBackend.pauseCalls;
      await tester.tap(pauseBtnInSheet);
      await tester.pumpAndSettle();

      // Пауза должна сработать с первого же нажатия (pause() ровно +1 раз).
      expect(fakeBackend.pauseCalls, pauseBefore + 1);
      expect(fakeBackend.currentPlaying, isFalse);
      expect(
        find.descendant(
          of: find.byType(NowPlayingSheet),
          matching: find.byTooltip('Воспроизвести'),
        ),
        findsOneWidget,
      );
    },
  );

  test('Пересчёт длительности CBR MP3 по префиксу сохраняет точное время', () {
    // 60 КБ ID3v2 + 20 КБ аудио в 80 КБ префиксе = 500 мс при 320 kbps,
    // а полный файл имеет 10 060 000 байт (ровно 250 секунд = 250 000 мс).
    final estimated = LibraryScannerService.estimatePartialCbrDurationMs(
      prefixDurationMs: 500,
      prefixLengthBytes: 80000,
      fullFileSizeBytes: 10060000,
      bitrateBps: 320000,
    );
    expect(estimated, 250000);
  });

  testWidgets('ArtworkBox показывает заглушку при отсутствующем файле обложки', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PyureTheme.dark(),
        home: const Scaffold(
          body: Center(
            child: ArtworkBox(
              artworkPath: r'C:\nonexistent_pyure_art\missing.jpg',
              size: 120,
            ),
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 20 && find.byIcon(Icons.music_note_rounded).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });

  testWidgets('ArtworkBox декодирует существующий локальный PNG в RawImage', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('pyure_art_test_');
    try {
      final pngFile = File('${tempDir.path}${Platform.pathSeparator}cover.png');
      // Минимальный валидный 1x1 RGBA PNG (рассчитано с корректными zlib/CRC).
      pngFile.writeAsBytesSync(const <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
        0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99,
        0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
        0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: PyureTheme.dark(),
          home: Scaffold(
            body: Center(
              child: ArtworkBox(
                artworkPath: pngFile.path,
                size: 120,
              ),
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 20 && find.byType(RawImage).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.byIcon(Icons.music_note_rounded), findsNothing);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('AndroidBackgroundScanGuard отправляет команды start/update/stop по каналу', () async {
    const channel = MethodChannel('com.pyure.player/background_scan_test');
    final recordedCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      recordedCalls.add(call);
      return null;
    });

    try {
      final guard = AndroidBackgroundScanGuard(channel: channel);
      await guard.startScan(folderName: 'Music');
      await guard.updateProgress(
        processed: 120,
        total: 3773,
        fileName: 'track.mp3',
      );
      await guard.stopScan();
      await guard.updateProgress(
        processed: 121,
        total: 3773,
        fileName: 'ignored_after_stop.mp3',
      );

      expect(recordedCalls.map((c) => c.method).toList(), [
        'startScan',
        'updateScanProgress',
        'stopScan',
      ]);
      expect(recordedCalls[0].arguments, {'folderName': 'Music'});
      expect(recordedCalls[1].arguments, {
        'processed': 120,
        'total': 3773,
        'fileName': 'track.mp3',
      });
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  test('LibraryNotifier запускает и останавливает BackgroundScanGuard даже при ошибке', () async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    final prefs = AppPreferences(sp);
    const folder = MusicFolderRef(
      uri: r'C:\Music',
      displayName: 'Music',
      isSafTree: false,
    );
    await prefs.setSelectedFolder(folder);

    final guard = _SpyBackgroundScanGuard();
    var shouldThrow = false;
    final scanner = _FakeLibraryScannerService(
      storageSource: _FakeMusicStorageSource(),
      database: _FakeAppDatabase(const []),
      onScan: (onProgress) async {
        onProgress(
          const ScanProgress(
            totalFound: 2,
            processed: 1,
            currentFileName: '01.mp3',
          ),
        );
        if (shouldThrow) {
          throw StateError('Simulated SAF error');
        }
        onProgress(
          const ScanProgress(
            totalFound: 2,
            processed: 2,
            currentFileName: '02.mp3',
          ),
        );
      },
    );

    final container = ProviderContainer(
      overrides: [
        appPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(_FakeAppDatabase(const [])),
        musicStorageSourceProvider.overrideWithValue(_FakeMusicStorageSource()),
        libraryScannerProvider.overrideWithValue(scanner),
        backgroundScanGuardProvider.overrideWithValue(guard),
      ],
    );
    addTearDown(container.dispose);

    await container.read(libraryProvider.notifier).rescanLibrary();
    expect(guard.events.first, 'start:Music');
    expect(guard.events.last, 'stop');
    expect(guard.updateCount, greaterThanOrEqualTo(1));

    guard.events.clear();
    shouldThrow = true;
    await container.read(libraryProvider.notifier).rescanLibrary();
    expect(guard.events, containsAllInOrder(['start:Music', 'stop']));
    expect(container.read(libraryProvider).isScanning, isFalse);
  });

  test('ArtworkBox.resolveCacheWidth разделяет ключи сетки и детального экрана', () {
    expect(ArtworkBox.resolveCacheWidth(null), 256);
    expect(ArtworkBox.resolveCacheWidth(46), 128);
    expect(ArtworkBox.resolveCacheWidth(180), 360);
    expect(ArtworkBox.resolveCacheWidth(200), 400);
    expect(ArtworkBox.resolveCacheWidth(320), 512);
  });

  testWidgets('ArtworkBox корректно декодирует 10+ разных обложек через очередь', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('pyure_queue_art_');
    const pngBytes = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
      0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99,
      0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
      0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];
    try {
      final paths = <String>[];
      for (var i = 0; i < 12; i++) {
        final f = File('${tempDir.path}${Platform.pathSeparator}c_$i.png');
        f.writeAsBytesSync(pngBytes);
        paths.add(f.path);
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: PyureTheme.dark(),
          home: Scaffold(
            body: Wrap(
              children: [
                for (final path in paths)
                  ArtworkBox(artworkPath: path, size: 80),
              ],
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 30 && find.byType(RawImage).evaluate().length < 12;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      expect(find.byType(RawImage), findsNWidgets(12));
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}

class _SpyBackgroundScanGuard implements BackgroundScanGuard {
  final List<String> events = [];
  int updateCount = 0;

  @override
  Future<void> startScan({required String folderName}) async {
    events.add('start:$folderName');
  }

  @override
  Future<void> updateProgress({
    required int processed,
    required int total,
    required String fileName,
  }) async {
    updateCount++;
    events.add('update:$processed/$total');
  }

  @override
  Future<void> stopScan() async {
    events.add('stop');
  }
}

class _FakeLibraryScannerService extends LibraryScannerService {
  _FakeLibraryScannerService({
    required super.storageSource,
    required super.database,
    required this.onScan,
  });

  final Future<void> Function(void Function(ScanProgress progress) onProgress)
  onScan;

  @override
  Future<void> scanFolder(
    MusicFolderRef folder, {
    required void Function(ScanProgress progress) onProgress,
  }) => onScan(onProgress);
}
