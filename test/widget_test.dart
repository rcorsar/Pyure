import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pyure/app/app.dart';
import 'package:pyure/core/database/app_database.dart';
import 'package:pyure/core/models/album.dart';
import 'package:pyure/core/models/album_sort_order.dart';
import 'package:pyure/core/models/track.dart';
import 'package:pyure/core/models/track_sort_order.dart';
import 'package:pyure/core/platform/music_source.dart';
import 'package:pyure/core/preferences/app_preferences.dart';
import 'package:pyure/core/utils/formatters.dart';
import 'package:pyure/features/library/data/metadata_fallback_resolver.dart';
import 'package:pyure/features/library/presentation/library_provider.dart';
import 'package:pyure/features/player/data/audio_playback_backend.dart';
import 'package:pyure/features/player/data/system_media_bridge.dart';
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
}

class _FakePlaybackBackend implements AudioPlaybackBackend {
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _completed = StreamController<bool>.broadcast();

  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration> get durationStream => _duration.stream;
  @override
  Stream<bool> get completedStream => _completed.stream;

  @override
  Future<void> open(String source, {required bool play}) async {
    _playing.add(play);
  }

  @override
  Future<void> pause() async => _playing.add(false);

  @override
  Future<void> play() async => _playing.add(true);

  @override
  Future<void> playOrPause() async => _playing.add(true);

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
}
