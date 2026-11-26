import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/track.dart';
import '../../../core/platform/music_source.dart';
import '../../../core/utils/formatters.dart';
import 'metadata_fallback_resolver.dart';

/// Прогресс сканирования музыкальной папки.
class ScanProgress {
  const ScanProgress({
    required this.totalFound,
    required this.processed,
    required this.currentFileName,
  });

  final int totalFound;
  final int processed;
  final String currentFileName;

  double? get fraction => totalFound > 0 ? processed / totalFound : null;
}

typedef _RawId3Payload = ({
  String? title,
  String? artist,
  String? album,
  int? trackNumber,
  int durationMs,
  Uint8List? coverBytes,
});

/// Сервис индексации MP3-файлов, чтения ID3-тегов и кэширования обложек.
class LibraryScannerService {
  LibraryScannerService({
    required this.storageSource,
    required this.database,
  });

  final MusicStorageSource storageSource;
  final AppDatabase database;

  Future<void> scanFolder(
    MusicFolderRef folder, {
    required void Function(ScanProgress progress) onProgress,
  }) async {
    onProgress(
      const ScanProgress(totalFound: 0, processed: 0, currentFileName: ''),
    );

    final entries = await storageSource.listMp3Entries(folder);
    final existingByUri = await database.getExistingTrackIndex();
    final artworkDir = await _ensureArtworkDir();
    final siblingCoverCache = <String, String?>{};

    final updatedOrNewTracks = <Track>[];
    final activeSourceUris = <String>{};
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      activeSourceUris.add(entry.sourceUri);

      onProgress(
        ScanProgress(
          totalFound: entries.length,
          processed: i + 1,
          currentFileName: entry.fileName,
        ),
      );

      final existing = existingByUri[entry.sourceUri];
      final isUnchanged =
          existing != null &&
          existing.fileSizeBytes == entry.sizeBytes &&
          existing.lastModifiedMs == entry.modifiedMs &&
          (existing.artworkPath == null ||
              await File(existing.artworkPath!).exists());

      if (isUnchanged) {
        continue;
      }

      final raw = await storageSource.withReadableFile<_RawId3Payload?>(
        entry.sourceUri,
        (file) => _parseInBackground(file.path),
      );

      String? artworkPath;
      final embeddedCoverBytes = raw?.coverBytes;
      if (embeddedCoverBytes != null && embeddedCoverBytes.isNotEmpty) {
        artworkPath = await _cacheCoverBytes(artworkDir, embeddedCoverBytes);
      } else if (entry.siblingCoverUri != null) {
        final coverUri = entry.siblingCoverUri!;
        if (siblingCoverCache.containsKey(coverUri)) {
          artworkPath = siblingCoverCache[coverUri];
        } else {
          final bytes = await storageSource.readBytes(coverUri);
          artworkPath = bytes != null && bytes.isNotEmpty
              ? await _cacheCoverBytes(artworkDir, bytes)
              : null;
          siblingCoverCache[coverUri] = artworkPath;
        }
      }

      final resolved = MetadataFallbackResolver.resolve(
        entry: entry,
        tagTitle: raw?.title,
        tagArtist: raw?.artist,
        tagAlbum: raw?.album,
        tagTrackNumber: raw?.trackNumber,
      );

      updatedOrNewTracks.add(
        Track(
          id: existing?.id ?? 0,
          title: resolved.title,
          artist: resolved.artist,
          album: resolved.album,
          albumKey: resolved.albumKey,
          trackNumber: resolved.trackNumber,
          sourceUri: entry.sourceUri,
          folderUri: folder.uri,
          parentFolderName: entry.parentFolderName,
          durationMs: raw?.durationMs ?? 0,
          artworkPath: artworkPath,
          addedAtEpochMs: existing?.addedAtEpochMs ?? nowEpochMs + i,
          fileSizeBytes: entry.sizeBytes,
          lastModifiedMs: entry.modifiedMs,
        ),
      );
    }

    await database.syncFolderTracks(
      folderUri: folder.uri,
      updatedOrNewTracks: updatedOrNewTracks,
      activeSourceUris: activeSourceUris,
    );
  }

  static Future<_RawId3Payload?> _parseInBackground(String filePath) {
    return Isolate.run<_RawId3Payload?>(() {
      try {
        final metadata = readMetadata(File(filePath), getImage: true);
        Uint8List? coverBytes;
        if (metadata.pictures.isNotEmpty) {
          final firstBytes = metadata.pictures.first.bytes;
          if (firstBytes.isNotEmpty) {
            coverBytes = firstBytes;
          }
        }
        return (
          title: metadata.title,
          artist: metadata.artist,
          album: metadata.album,
          trackNumber: metadata.trackNumber,
          durationMs: metadata.duration?.inMilliseconds ?? 0,
          coverBytes: coverBytes,
        );
      } on MetadataParserException {
        return null;
      } catch (_) {
        return null;
      }
    });
  }

  Future<Directory> _ensureArtworkDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final artDir = Directory(p.join(supportDir.path, 'pyure_artwork'));
    if (!await artDir.exists()) {
      await artDir.create(recursive: true);
    }
    return artDir;
  }

  Future<String> _cacheCoverBytes(Directory artDir, Uint8List bytes) async {
    final isPng =
        bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final ext = isPng ? 'png' : 'jpg';
    final fileName = '${stableBytesHash(bytes)}.$ext';
    final file = File(p.join(artDir.path, fileName));
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: false);
    }
    return file.path;
  }
}
