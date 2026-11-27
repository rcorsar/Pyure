import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/track.dart';
import '../models/track_sort_order.dart';

/// Инициализирует FFI-драйвер SQLite для десктопных платформ.
void initDesktopDatabaseIfNeeded() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

/// Метаданные существующей записи в БД для инкрементального пересканирования.
class ExistingTrackRecord {
  const ExistingTrackRecord({
    required this.id,
    required this.sourceUri,
    required this.fileSizeBytes,
    required this.lastModifiedMs,
    required this.addedAtEpochMs,
    this.artworkPath,
  });

  final int id;
  final String sourceUri;
  final int fileSizeBytes;
  final int lastModifiedMs;
  final int addedAtEpochMs;
  final String? artworkPath;
}

/// Локальное хранилище треков на базе SQLite (`sqflite` + `sqflite_common_ffi`).
class AppDatabase {
  AppDatabase({this.overridePath});

  final String? overridePath;
  Database? _db;

  static const int _schemaVersion = 1;

  Future<Database> _getDb() async {
    if (_db != null && _db!.isOpen) return _db!;

    final String dbPath;
    if (overridePath != null) {
      dbPath = overridePath!;
    } else {
      final supportDir = await getApplicationSupportDirectory();
      if (!await supportDir.exists()) {
        await supportDir.create(recursive: true);
      }
      dbPath = p.join(supportDir.path, 'pyure_library.db');
    }

    _db = await openDatabase(
      dbPath,
      version: _schemaVersion,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode = WAL');
        await db.rawQuery('PRAGMA synchronous = NORMAL');
        await db.rawQuery('PRAGMA temp_store = MEMORY');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT NOT NULL,
            album_key TEXT NOT NULL,
            title_norm TEXT NOT NULL,
            artist_norm TEXT NOT NULL,
            album_norm TEXT NOT NULL,
            track_number INTEGER,
            source_uri TEXT NOT NULL UNIQUE,
            folder_uri TEXT NOT NULL,
            parent_folder_name TEXT NOT NULL,
            duration_ms INTEGER NOT NULL,
            artwork_path TEXT,
            added_at_epoch_ms INTEGER NOT NULL,
            file_size_bytes INTEGER NOT NULL,
            last_modified_ms INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_tracks_album_key ON tracks (album_key)',
        );
        await db.execute(
          'CREATE INDEX idx_tracks_title_norm ON tracks (title_norm)',
        );
        await db.execute(
          'CREATE INDEX idx_tracks_artist_norm ON tracks (artist_norm)',
        );
        await db.execute(
          'CREATE INDEX idx_tracks_album_norm ON tracks (album_norm)',
        );
        await db.execute(
          'CREATE INDEX idx_tracks_added_at ON tracks (added_at_epoch_ms DESC)',
        );
      },
    );
    return _db!;
  }

  Future<Map<String, ExistingTrackRecord>> getExistingTrackIndex() async {
    final db = await _getDb();
    final rows = await db.query(
      'tracks',
      columns: const [
        'id',
        'source_uri',
        'file_size_bytes',
        'last_modified_ms',
        'added_at_epoch_ms',
        'artwork_path',
      ],
    );

    final map = <String, ExistingTrackRecord>{};
    for (final row in rows) {
      final uri = row['source_uri'] as String;
      map[uri] = ExistingTrackRecord(
        id: row['id'] as int,
        sourceUri: uri,
        fileSizeBytes: row['file_size_bytes'] as int,
        lastModifiedMs: row['last_modified_ms'] as int,
        addedAtEpochMs: row['added_at_epoch_ms'] as int,
        artworkPath: row['artwork_path'] as String?,
      );
    }
    return map;
  }

  /// Синхронизирует библиотеку с текущим набором треков:
  /// обновляет изменённые, добавляет новые и удаляет отсутствующие файлы.
  Future<void> syncFolderTracks({
    required String folderUri,
    required List<Track> updatedOrNewTracks,
    required Set<String> activeSourceUris,
  }) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      // Удаляем треки из других папок или исчезнувшие из выбранной папки.
      final existingRows = await txn.query(
        'tracks',
        columns: const ['id', 'source_uri', 'folder_uri'],
      );
      final idsToDelete = <int>[];
      final existingIdByUri = <String, int>{};

      for (final row in existingRows) {
        final id = row['id'] as int;
        final uri = row['source_uri'] as String;
        final rowFolder = row['folder_uri'] as String;
        if (rowFolder != folderUri || !activeSourceUris.contains(uri)) {
          idsToDelete.add(id);
        } else {
          existingIdByUri[uri] = id;
        }
      }

      final batch = txn.batch();
      if (idsToDelete.isNotEmpty) {
        const chunkSize = 400;
        for (var i = 0; i < idsToDelete.length; i += chunkSize) {
          final end = (i + chunkSize < idsToDelete.length)
              ? i + chunkSize
              : idsToDelete.length;
          final slice = idsToDelete.sublist(i, end);
          final placeholders = List.filled(slice.length, '?').join(',');
          batch.delete(
            'tracks',
            where: 'id IN ($placeholders)',
            whereArgs: slice,
          );
        }
      }

      for (final track in updatedOrNewTracks) {
        final values = track.toInsertMap();
        final existingId = existingIdByUri[track.sourceUri];
        if (existingId != null) {
          batch.update(
            'tracks',
            values,
            where: 'id = ?',
            whereArgs: [existingId],
          );
        } else {
          batch.insert('tracks', values);
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Track>> getAllTracks({
    TrackSortOrder sortOrder = TrackSortOrder.title,
  }) async {
    final db = await _getDb();
    final orderBy = switch (sortOrder) {
      TrackSortOrder.title => 'title_norm ASC, artist_norm ASC',
      TrackSortOrder.album =>
        'album_norm ASC, COALESCE(track_number, 999999) ASC, title_norm ASC',
      TrackSortOrder.addedAt => 'added_at_epoch_ms DESC, id DESC',
    };

    final rows = await db.query('tracks', orderBy: orderBy);
    return rows.map(Track.fromMap).toList(growable: false);
  }

  Future<List<Track>> getTracksByAlbum(String albumKey) async {
    final db = await _getDb();
    final rows = await db.query(
      'tracks',
      where: 'album_key = ?',
      whereArgs: [albumKey],
      orderBy: 'COALESCE(track_number, 999999) ASC, title_norm ASC',
    );
    return rows.map(Track.fromMap).toList(growable: false);
  }

  Future<Track?> findTrackByIdOrUri({int? id, String? sourceUri}) async {
    final db = await _getDb();
    if (id != null) {
      final rows = await db.query(
        'tracks',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) return Track.fromMap(rows.first);
    }
    if (sourceUri != null && sourceUri.isNotEmpty) {
      final rows = await db.query(
        'tracks',
        where: 'source_uri = ?',
        whereArgs: [sourceUri],
        limit: 1,
      );
      if (rows.isNotEmpty) return Track.fromMap(rows.first);
    }
    return null;
  }

  /// Мгновенный поиск с поддержкой кириллического регистра (через `*_norm`).
  Future<List<Track>> searchTracks(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];

    final escaped = normalized
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final pattern = '%$escaped%';

    final db = await _getDb();
    final rows = await db.query(
      'tracks',
      where:
          "title_norm LIKE ? ESCAPE '\\' "
          "OR artist_norm LIKE ? ESCAPE '\\' "
          "OR album_norm LIKE ? ESCAPE '\\'",
      whereArgs: [pattern, pattern, pattern],
      orderBy: 'title_norm ASC, artist_norm ASC',
    );
    return rows.map(Track.fromMap).toList(growable: false);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
