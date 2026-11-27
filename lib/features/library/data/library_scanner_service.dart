import 'dart:async';
import 'dart:collection';
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
  String? artworkPath,
  bool hasLeadingId3v2,
  bool isPartialRead,
});

/// Сервис индексации MP3-файлов, чтения ID3-тегов и кэширования обложек.
class LibraryScannerService {
  LibraryScannerService({
    required this.storageSource,
    required this.database,
  });

  final MusicStorageSource storageSource;
  final AppDatabase database;

  /// Корректирует длительность CBR MP3 при префиксном чтении заголовка,
  /// зная длину прочитанного префикса и полный размер исходного файла.
  static int estimatePartialCbrDurationMs({
    required int prefixDurationMs,
    required int prefixLengthBytes,
    required int fullFileSizeBytes,
    required int bitrateBps,
  }) {
    if (prefixDurationMs <= 0 ||
        bitrateBps <= 0 ||
        fullFileSizeBytes <= prefixLengthBytes) {
      return prefixDurationMs;
    }
    final audioInPrefixBytes = (prefixDurationMs / 1000.0) * (bitrateBps / 8.0);
    final headerOverhead = (prefixLengthBytes - audioInPrefixBytes).clamp(
      0.0,
      prefixLengthBytes.toDouble(),
    );
    final totalAudioBytes = (fullFileSizeBytes - headerOverhead).clamp(
      0.0,
      fullFileSizeBytes.toDouble(),
    );
    return ((8.0 * totalAudioBytes / bitrateBps) * 1000.0).round();
  }

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
    final knownArtworkFiles = await _listExistingArtworkNames(artworkDir);
    final siblingCoverFutures = <String, Future<String?>>{};

    final activeSourceUris = <String>{};
    final toParse = <({int index, ScannedAudioEntry entry, ExistingTrackRecord? existing})>[];
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    var processedCount = 0;

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      activeSourceUris.add(entry.sourceUri);

      final existing = existingByUri[entry.sourceUri];
      final existingArt = existing?.artworkPath;
      final hasValidExistingArt =
          existingArt == null ||
          existingArt.isEmpty ||
          knownArtworkFiles.contains(p.basename(existingArt));
      final isUnchanged =
          existing != null &&
          existing.fileSizeBytes == entry.sizeBytes &&
          existing.lastModifiedMs == entry.modifiedMs &&
          hasValidExistingArt;

      if (isUnchanged) {
        processedCount++;
        continue;
      }
      toParse.add((index: i, entry: entry, existing: existing));
    }

    onProgress(
      ScanProgress(
        totalFound: entries.length,
        processed: processedCount,
        currentFileName: entries.isNotEmpty ? entries.first.fileName : '',
      ),
    );

    final updatedOrNewTracks = <Track>[];
    if (toParse.isNotEmpty) {
      final workerCount = Platform.numberOfProcessors.clamp(2, 4);
      final pool = await _MetadataWorkerPool.start(workerCount);
      final queue = Queue.of(toParse);
      var lastProgressEmitMs = 0;

      Future<void> runWorkerLoop() async {
        while (queue.isNotEmpty) {
          final task = queue.removeFirst();
          final entry = task.entry;
          final existing = task.existing;

          var raw = await storageSource.withMetadataFile<_RawId3Payload?>(
            entry,
            (file, fullSizeBytes) => pool.parse(
              filePath: file.path,
              artworkDirPath: artworkDir.path,
              fullFileSizeBytes: fullSizeBytes,
            ),
          );

          // Если файл без ведущего ID3v2 и в префиксе нет тегов, пробуем
          // прочитать весь файл (для ID3v1 / APEv2 в конце файла).
          if (raw != null &&
              raw.isPartialRead &&
              !raw.hasLeadingId3v2 &&
              raw.title == null &&
              raw.artworkPath == null &&
              entry.sizeBytes > 0 &&
              entry.sizeBytes <= 32 * 1024 * 1024) {
            raw = await storageSource.withReadableFile<_RawId3Payload?>(
              entry.sourceUri,
              (file) => pool.parse(
                filePath: file.path,
                artworkDirPath: artworkDir.path,
                fullFileSizeBytes: entry.sizeBytes,
              ),
            );
          }

          var artworkPath = raw?.artworkPath;
          if (artworkPath == null && entry.siblingCoverUri != null) {
            final coverUri = entry.siblingCoverUri!;
            artworkPath = await siblingCoverFutures.putIfAbsent(
              coverUri,
              () async {
                final bytes = await storageSource.readBytes(coverUri);
                if (bytes == null || bytes.isEmpty) return null;
                return _cacheCoverBytes(artworkDir, bytes);
              },
            );
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
              addedAtEpochMs: existing?.addedAtEpochMs ?? nowEpochMs + task.index,
              fileSizeBytes: entry.sizeBytes,
              lastModifiedMs: entry.modifiedMs,
            ),
          );

          processedCount++;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - lastProgressEmitMs >= 75 ||
              processedCount == entries.length) {
            lastProgressEmitMs = nowMs;
            onProgress(
              ScanProgress(
                totalFound: entries.length,
                processed: processedCount,
                currentFileName: entry.fileName,
              ),
            );
          }
        }
      }

      try {
        await Future.wait([
          for (var w = 0; w < workerCount; w++) runWorkerLoop(),
        ]);
      } finally {
        await pool.dispose();
      }
    }

    await database.syncFolderTracks(
      folderUri: folder.uri,
      updatedOrNewTracks: updatedOrNewTracks,
      activeSourceUris: activeSourceUris,
    );
  }

  Future<Set<String>> _listExistingArtworkNames(Directory artDir) async {
    final names = <String>{};
    try {
      await for (final entity in artDir.list(followLinks: false)) {
        if (entity is File) {
          names.add(p.basename(entity.path));
        }
      }
    } catch (_) {}
    return names;
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
    final path = _resolveArtworkFilePath(artDir.path, bytes);
    final file = File(path);
    if (!await file.exists()) {
      await _writeFileAtomic(file, bytes);
    }
    return file.path;
  }
}

String _resolveArtworkFilePath(String artDirPath, Uint8List bytes) {
  final isPng =
      bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;
  final ext = isPng ? 'png' : 'jpg';
  return p.join(artDirPath, '${stableBytesHash(bytes)}.$ext');
}

Future<void> _writeFileAtomic(File targetFile, Uint8List bytes) async {
  final tmp = File(
    '${targetFile.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await tmp.writeAsBytes(bytes, flush: false);
    if (!await targetFile.exists()) {
      await tmp.rename(targetFile.path);
    } else {
      await tmp.delete();
    }
  } catch (_) {
    if (await tmp.exists()) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}

class _MetadataWorkerPool {
  _MetadataWorkerPool._(this._workers);

  final List<_IsolateWorker> _workers;
  int _nextWorker = 0;

  static Future<_MetadataWorkerPool> start(int count) async {
    final workers = await Future.wait([
      for (var i = 0; i < count; i++) _IsolateWorker.spawn(i),
    ]);
    return _MetadataWorkerPool._(workers);
  }

  Future<_RawId3Payload?> parse({
    required String filePath,
    required String artworkDirPath,
    required int fullFileSizeBytes,
  }) {
    final worker = _workers[_nextWorker];
    _nextWorker = (_nextWorker + 1) % _workers.length;
    return worker.parse(
      filePath: filePath,
      artworkDirPath: artworkDirPath,
      fullFileSizeBytes: fullFileSizeBytes,
    );
  }

  Future<void> dispose() async {
    for (final worker in _workers) {
      worker.dispose();
    }
  }
}

class _IsolateWorker {
  _IsolateWorker._(this._isolate, this._sendPort, this._receivePort);

  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _receivePort;
  final Map<int, Completer<_RawId3Payload?>> _pending = {};
  int _nextTaskId = 0;

  static Future<_IsolateWorker> spawn(int workerIndex) async {
    final initPort = ReceivePort();
    final isolate = await Isolate.spawn(_workerEntry, (
      port: initPort.sendPort,
      workerIndex: workerIndex,
    ));
    final sendPort = await initPort.first as SendPort;
    initPort.close();

    final responsePort = ReceivePort();
    sendPort.send(responsePort.sendPort);
    final worker = _IsolateWorker._(isolate, sendPort, responsePort);
    responsePort.listen(worker._onMessage);
    return worker;
  }

  void _onMessage(dynamic message) {
    final res = message as ({int id, _RawId3Payload? payload});
    final completer = _pending.remove(res.id);
    completer?.complete(res.payload);
  }

  Future<_RawId3Payload?> parse({
    required String filePath,
    required String artworkDirPath,
    required int fullFileSizeBytes,
  }) {
    final id = _nextTaskId++;
    final completer = Completer<_RawId3Payload?>();
    _pending[id] = completer;
    _sendPort.send((
      id: id,
      filePath: filePath,
      artworkDirPath: artworkDirPath,
      fullFileSizeBytes: fullFileSizeBytes,
    ));
    return completer.future;
  }

  void dispose() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _pending.clear();
    _sendPort.send(null);
    _receivePort.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }
}

void _workerEntry(({SendPort port, int workerIndex}) init) {
  final inbox = ReceivePort();
  init.port.send(inbox.sendPort);
  SendPort? replyPort;

  inbox.listen((dynamic message) {
    if (message is SendPort) {
      replyPort = message;
      return;
    }
    if (message == null) {
      inbox.close();
      return;
    }
    final req = message as ({
      int id,
      String filePath,
      String artworkDirPath,
      int fullFileSizeBytes,
    });
    final payload = _parseTrackSync(
      filePath: req.filePath,
      artworkDirPath: req.artworkDirPath,
      fullFileSizeBytes: req.fullFileSizeBytes,
      workerIndex: init.workerIndex,
    );
    replyPort?.send((id: req.id, payload: payload));
  });
}

_RawId3Payload? _parseTrackSync({
  required String filePath,
  required String artworkDirPath,
  required int fullFileSizeBytes,
  required int workerIndex,
}) {
  try {
    final file = File(filePath);
    final actualLen = file.lengthSync();
    final isPartialRead = fullFileSizeBytes > 0 && actualLen < fullFileSizeBytes;
    final hasLeadingId3 = _fileStartsWithId3(file, actualLen);

    final metadata = readMetadata(file, getImage: true);
    var durationMs = metadata.duration?.inMilliseconds ?? 0;

    if (isPartialRead &&
        durationMs > 0 &&
        metadata.bitrate != null &&
        metadata.bitrate! > 0) {
      final hasVbrHeader = _fileHasVbrHeader(file, actualLen);
      if (!hasVbrHeader) {
        durationMs = LibraryScannerService.estimatePartialCbrDurationMs(
          prefixDurationMs: durationMs,
          prefixLengthBytes: actualLen,
          fullFileSizeBytes: fullFileSizeBytes,
          bitrateBps: metadata.bitrate!,
        );
      }
    }

    String? artworkPath;
    if (metadata.pictures.isNotEmpty) {
      final coverBytes = metadata.pictures.first.bytes;
      if (coverBytes.isNotEmpty) {
        final targetPath = _resolveArtworkFilePath(artworkDirPath, coverBytes);
        final targetFile = File(targetPath);
        if (!targetFile.existsSync()) {
          final tmp = File('$targetPath.w$workerIndex.tmp');
          try {
            tmp.writeAsBytesSync(coverBytes, flush: false);
            if (!targetFile.existsSync()) {
              tmp.renameSync(targetPath);
            } else {
              tmp.deleteSync();
            }
          } catch (_) {
            if (tmp.existsSync()) {
              try {
                tmp.deleteSync();
              } catch (_) {}
            }
          }
        }
        if (targetFile.existsSync()) {
          artworkPath = targetPath;
        }
      }
    }

    return (
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album,
      trackNumber: metadata.trackNumber,
      durationMs: durationMs,
      artworkPath: artworkPath,
      hasLeadingId3v2: hasLeadingId3,
      isPartialRead: isPartialRead,
    );
  } on MetadataParserException {
    return null;
  } catch (_) {
    return null;
  }
}

bool _fileStartsWithId3(File file, int length) {
  if (length < 10) return false;
  final raf = file.openSync();
  try {
    final hdr = raf.readSync(3);
    return hdr.length == 3 && hdr[0] == 0x49 && hdr[1] == 0x44 && hdr[2] == 0x33;
  } finally {
    raf.closeSync();
  }
}

bool _fileHasVbrHeader(File file, int length) {
  if (length < 128) return false;
  final raf = file.openSync();
  try {
    var offset = 0;
    while (offset + 10 <= length) {
      raf.setPositionSync(offset);
      final hdr = raf.readSync(10);
      if (hdr.length < 10 ||
          hdr[0] != 0x49 ||
          hdr[1] != 0x44 ||
          hdr[2] != 0x33 ||
          (hdr[6] & 0x80) != 0 ||
          (hdr[7] & 0x80) != 0 ||
          (hdr[8] & 0x80) != 0 ||
          (hdr[9] & 0x80) != 0) {
        break;
      }
      final tagSize =
          (hdr[9] & 0x7F) |
          ((hdr[8] & 0x7F) << 7) |
          ((hdr[7] & 0x7F) << 14) |
          ((hdr[6] & 0x7F) << 21);
      final hasFooter = hdr[3] == 4 && (hdr[5] & 0x10) != 0;
      offset += 10 + tagSize + (hasFooter ? 10 : 0);
    }
    if (offset >= length) return false;
    raf.setPositionSync(offset);
    final toRead = (length - offset).clamp(0, 8192);
    final window = raf.readSync(toRead);
    for (var i = 0; i <= window.length - 4; i++) {
      final b0 = window[i];
      if ((b0 == 0x58 &&
              window[i + 1] == 0x69 &&
              window[i + 2] == 0x6E &&
              window[i + 3] == 0x67) || // Xing
          (b0 == 0x49 &&
              window[i + 1] == 0x6E &&
              window[i + 2] == 0x66 &&
              window[i + 3] == 0x6F) || // Info
          (b0 == 0x56 &&
              window[i + 1] == 0x42 &&
              window[i + 2] == 0x52 &&
              window[i + 3] == 0x49)) { // VBRI
        return true;
      }
    }
    return false;
  } catch (_) {
    return false;
  } finally {
    raf.closeSync();
  }
}
