import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/album.dart';
import '../../../core/models/album_sort_order.dart';
import '../../../core/models/track.dart';
import '../../../core/models/track_sort_order.dart';
import '../../../core/platform/music_source.dart';
import '../../../core/preferences/app_preferences.dart';
import '../data/library_scanner_service.dart';
import '../data/metadata_fallback_resolver.dart';

/// Провайдер настроек (переопределяется в `main.dart` и тестах).
final appPreferencesProvider = Provider<AppPreferences>((ref) {
  throw UnimplementedError('AppPreferences must be overridden in ProviderScope');
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() {
    unawaited(db.close());
  });
  return db;
});

final musicStorageSourceProvider = Provider<MusicStorageSource>((ref) {
  return createMusicStorageSource();
});

final libraryScannerProvider = Provider<LibraryScannerService>((ref) {
  return LibraryScannerService(
    storageSource: ref.watch(musicStorageSourceProvider),
    database: ref.watch(appDatabaseProvider),
  );
});

@immutable
class LibraryState {
  const LibraryState({
    this.selectedFolder,
    this.tracks = const [],
    this.albums = const [],
    this.sortOrder = TrackSortOrder.title,
    this.albumSortOrder = AlbumSortOrder.artist,
    this.isInitialLoading = true,
    this.isScanning = false,
    this.scanProcessed = 0,
    this.scanTotal = 0,
    this.currentScanFile = '',
    this.errorMessage,
  });

  final MusicFolderRef? selectedFolder;
  final List<Track> tracks;
  final List<Album> albums;
  final TrackSortOrder sortOrder;
  final AlbumSortOrder albumSortOrder;
  final bool isInitialLoading;
  final bool isScanning;
  final int scanProcessed;
  final int scanTotal;
  final String currentScanFile;
  final String? errorMessage;

  double? get scanFraction => scanTotal > 0 ? scanProcessed / scanTotal : null;

  LibraryState copyWith({
    MusicFolderRef? selectedFolder,
    bool clearFolder = false,
    List<Track>? tracks,
    List<Album>? albums,
    TrackSortOrder? sortOrder,
    AlbumSortOrder? albumSortOrder,
    bool? isInitialLoading,
    bool? isScanning,
    int? scanProcessed,
    int? scanTotal,
    String? currentScanFile,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LibraryState(
      selectedFolder: clearFolder
          ? null
          : (selectedFolder ?? this.selectedFolder),
      tracks: tracks ?? this.tracks,
      albums: albums ?? this.albums,
      sortOrder: sortOrder ?? this.sortOrder,
      albumSortOrder: albumSortOrder ?? this.albumSortOrder,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isScanning: isScanning ?? this.isScanning,
      scanProcessed: scanProcessed ?? this.scanProcessed,
      scanTotal: scanTotal ?? this.scanTotal,
      currentScanFile: currentScanFile ?? this.currentScanFile,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class LibraryNotifier extends Notifier<LibraryState> {
  @override
  LibraryState build() {
    final prefs = ref.watch(appPreferencesProvider);
    final initialFolder = prefs.getSelectedFolder();
    final initialSort = prefs.getTrackSortOrder();
    final initialAlbumSort = prefs.getAlbumSortOrder();

    Future.microtask(_loadCachedLibrary);

    return LibraryState(
      selectedFolder: initialFolder,
      sortOrder: initialSort,
      albumSortOrder: initialAlbumSort,
    );
  }

  Future<void> _loadCachedLibrary() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final tracks = await db.getAllTracks(sortOrder: state.sortOrder);
      if (!ref.mounted) return;
      state = state.copyWith(
        tracks: tracks,
        albums: MetadataFallbackResolver.aggregateAlbums(
          tracks,
          sortOrder: state.albumSortOrder,
        ),
        isInitialLoading: false,
        clearError: true,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isInitialLoading: false,
        errorMessage: 'Не удалось загрузить библиотеку: $e',
      );
    }
  }

  Future<void> pickFolderAndScan() async {
    if (state.isScanning) return;
    final storage = ref.read(musicStorageSourceProvider);

    try {
      final folder = await storage.pickMusicFolder();
      if (folder == null || !ref.mounted) return;

      await ref.read(appPreferencesProvider).setSelectedFolder(folder);
      if (!ref.mounted) return;

      state = state.copyWith(selectedFolder: folder, clearError: true);
      await _runScan(folder);
    } catch (e) {
      if (!ref.mounted) return;
      final hint = defaultTargetPlatform == TargetPlatform.android
          ? ' Выберите конкретную папку с музыкой (например Music), а не корень памяти.'
          : '';
      state = state.copyWith(
        errorMessage: 'Не удалось выбрать папку: $e$hint',
      );
    }
  }

  Future<void> rescanLibrary() async {
    if (state.isScanning) return;
    final folder = state.selectedFolder;
    if (folder == null) {
      await pickFolderAndScan();
      return;
    }

    final storage = ref.read(musicStorageSourceProvider);
    final hasAccess = await storage.hasPersistedAccess(folder);
    if (!ref.mounted) return;

    if (!hasAccess) {
      state = state.copyWith(
        errorMessage: 'Доступ к папке утрачен. Выберите папку заново.',
      );
      return;
    }

    await _runScan(folder);
  }

  Future<void> _runScan(MusicFolderRef folder) async {
    state = state.copyWith(
      isScanning: true,
      scanProcessed: 0,
      scanTotal: 0,
      currentScanFile: '',
      clearError: true,
    );

    try {
      final scanner = ref.read(libraryScannerProvider);
      await scanner.scanFolder(
        folder,
        onProgress: (progress) {
          if (!ref.mounted) return;
          state = state.copyWith(
            scanProcessed: progress.processed,
            scanTotal: progress.totalFound,
            currentScanFile: progress.currentFileName,
          );
        },
      );

      final db = ref.read(appDatabaseProvider);
      final tracks = await db.getAllTracks(sortOrder: state.sortOrder);
      if (!ref.mounted) return;

      state = state.copyWith(
        tracks: tracks,
        albums: MetadataFallbackResolver.aggregateAlbums(
          tracks,
          sortOrder: state.albumSortOrder,
        ),
        isScanning: false,
        isInitialLoading: false,
        clearError: true,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isScanning: false,
        errorMessage: 'Ошибка сканирования: $e',
      );
    }
  }

  Future<void> setSortOrder(TrackSortOrder order) async {
    if (state.sortOrder == order) return;
    await ref.read(appPreferencesProvider).setTrackSortOrder(order);
    final db = ref.read(appDatabaseProvider);
    final tracks = await db.getAllTracks(sortOrder: order);
    if (!ref.mounted) return;

    state = state.copyWith(
      sortOrder: order,
      tracks: tracks,
      albums: MetadataFallbackResolver.aggregateAlbums(
        tracks,
        sortOrder: state.albumSortOrder,
      ),
    );
  }

  Future<void> setAlbumSortOrder(AlbumSortOrder order) async {
    if (state.albumSortOrder == order) return;
    await ref.read(appPreferencesProvider).setAlbumSortOrder(order);
    if (!ref.mounted) return;

    state = state.copyWith(
      albumSortOrder: order,
      albums: MetadataFallbackResolver.sortAlbums(state.albums, order),
    );
  }
}

final libraryProvider = NotifierProvider<LibraryNotifier, LibraryState>(
  LibraryNotifier.new,
);

/// Провайдер треков конкретного альбома, отсортированных по номеру трека.
final albumTracksProvider = FutureProvider.family<List<Track>, String>((
  ref,
  albumKey,
) async {
  // Пересчитываем при изменении состава библиотеки.
  ref.watch(libraryProvider.select((s) => s.tracks.length));
  return ref.read(appDatabaseProvider).getTracksByAlbum(albumKey);
});

/// Провайдер результатов мгновенного поиска в SQLite.
final searchResultsProvider = FutureProvider.family<List<Track>, String>((
  ref,
  query,
) async {
  ref.watch(libraryProvider.select((s) => s.tracks.length));
  if (query.trim().isEmpty) return const [];
  return ref.read(appDatabaseProvider).searchTracks(query);
});
