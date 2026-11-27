import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart' show SafDocumentFile;

import '../utils/formatters.dart';
import 'music_source.dart';

/// Реализация [MusicStorageSource] для Android поверх Storage Access Framework
/// (`saf_util` + `saf_stream`), совместимая с GrapheneOS Storage Scopes
/// и не требующая `MANAGE_EXTERNAL_STORAGE`.
class AndroidSafMusicStorageSource implements MusicStorageSource {
  AndroidSafMusicStorageSource({
    SafUtil? safUtil,
    SafStream? safStream,
  }) : _safUtil = safUtil ?? SafUtil(),
       _safStream = safStream ?? SafStream();

  final SafUtil _safUtil;
  final SafStream _safStream;
  Future<Directory>? _cachedTempDir;

  static const List<String> _coverCandidates = [
    'cover.jpg',
    'folder.jpg',
    'cover.jpeg',
    'folder.jpeg',
    'cover.png',
    'folder.png',
  ];

  static const int _maxPlaybackCacheEntries = 4;
  static const int _prefixChunkBytes = 65536;
  static const int _headerTailPaddingBytes = 24576;
  static const int _maxPrefixScanBytes = 8 * 1024 * 1024;
  static const int _noId3v2PrefixBytes = 32768;

  Future<Directory> _getTempDir() => _cachedTempDir ??= getTemporaryDirectory();

  @override
  Future<MusicFolderRef?> pickMusicFolder() async {
    final picked = await _safUtil.pickDirectory(
      writePermission: false,
      persistablePermission: true,
    );
    if (picked == null) return null;

    return MusicFolderRef(
      uri: picked.uri,
      displayName: picked.name.isEmpty ? 'Музыка' : picked.name,
      isSafTree: true,
    );
  }

  @override
  Future<bool> hasPersistedAccess(MusicFolderRef folder) async {
    if (!folder.isSafTree) return false;
    try {
      if (await _safUtil.hasPersistedPermission(folder.uri)) {
        return true;
      }
    } catch (_) {}
    try {
      final stat = await _safUtil.stat(folder.uri, true);
      return stat != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<ScannedAudioEntry>> listMp3Entries(MusicFolderRef folder) async {
    await _cleanupStaleScanFiles();
    final entries = <ScannedAudioEntry>[];
    final pendingDirs = <({String dirUri, String folderName, bool isRootLevel})>[
      (dirUri: folder.uri, folderName: '', isRootLevel: true),
    ];
    const concurrency = 6;

    while (pendingDirs.isNotEmpty) {
      final batchCount = pendingDirs.length < concurrency
          ? pendingDirs.length
          : concurrency;
      final batch = pendingDirs.sublist(0, batchCount);
      pendingDirs.removeRange(0, batchCount);

      final results = await Future.wait([
        for (final node in batch)
          _listSingleSafDir(
            dirUri: node.dirUri,
            folderName: node.folderName,
            isRootLevel: node.isRootLevel,
          ),
      ]);

      for (final res in results) {
        entries.addAll(res.entries);
        pendingDirs.addAll(res.subDirs);
      }
    }

    return entries;
  }

  Future<void> _cleanupStaleScanFiles() async {
    try {
      final tempDir = await _getTempDir();
      await for (final entity in tempDir.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is File &&
            (name.startsWith('pyure_scan_') || name.startsWith('pyure_hdr_'))) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<
    ({
      List<ScannedAudioEntry> entries,
      List<({String dirUri, String folderName, bool isRootLevel})> subDirs,
    })
  >
  _listSingleSafDir({
    required String dirUri,
    required String folderName,
    required bool isRootLevel,
  }) async {
    List<SafDocumentFile> children;
    try {
      children = await _safUtil.list(dirUri);
    } catch (_) {
      return (
        entries: <ScannedAudioEntry>[],
        subDirs: <({String dirUri, String folderName, bool isRootLevel})>[],
      );
    }

    final subDirs =
        <({String dirUri, String folderName, bool isRootLevel})>[];
    final mp3Docs = <SafDocumentFile>[];
    String? siblingCoverUri;
    var bestCoverPriority = _coverCandidates.length;

    for (final doc in children) {
      final nameLower = doc.name.toLowerCase();
      if (doc.isDir) {
        if (nameLower.startsWith('.trashed') ||
            nameLower == '.trash' ||
            nameLower == '.trashes' ||
            nameLower == '.thumbnails' ||
            nameLower == 'lost+found') {
          continue;
        }
        subDirs.add((
          dirUri: doc.uri,
          folderName: doc.name,
          isRootLevel: false,
        ));
        continue;
      }
      if (!nameLower.startsWith('._') && nameLower.endsWith('.mp3')) {
        mp3Docs.add(doc);
      } else {
        final priority = _coverCandidates.indexOf(nameLower);
        if (priority != -1 && priority < bestCoverPriority) {
          bestCoverPriority = priority;
          siblingCoverUri = doc.uri;
        }
      }
    }

    final out = <ScannedAudioEntry>[
      for (final doc in mp3Docs)
        ScannedAudioEntry(
          sourceUri: doc.uri,
          fileName: doc.name,
          parentFolderName: folderName,
          isRootLevel: isRootLevel,
          sizeBytes: doc.length < 0 ? 0 : doc.length,
          modifiedMs: doc.lastModified,
          siblingCoverUri: siblingCoverUri,
        ),
    ];

    return (entries: out, subDirs: subDirs);
  }

  @override
  Future<Uint8List?> readBytes(String sourceUri) async {
    try {
      return await _safStream.readFileBytes(sourceUri);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<T> withReadableFile<T>(
    String sourceUri,
    Future<T> Function(File file) action,
  ) async {
    final tempDir = await _getTempDir();
    final tempFile = File(
      p.join(tempDir.path, 'pyure_scan_${stableHexHash(sourceUri)}.mp3'),
    );
    try {
      await _safStream.copyToLocalFile(sourceUri, tempFile.path);
      return await action(tempFile);
    } finally {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  @override
  Future<T> withMetadataFile<T>(
    ScannedAudioEntry entry,
    Future<T> Function(File file, int fullFileSizeBytes) action,
  ) async {
    final tempDir = await _getTempDir();
    final tempFile = File(
      p.join(tempDir.path, 'pyure_hdr_${stableHexHash(entry.sourceUri)}.mp3'),
    );

    Uint8List? prefixBytes;
    try {
      prefixBytes = await _readMetadataPrefixBytes(
        entry.sourceUri,
        knownSizeBytes: entry.sizeBytes,
      );
    } catch (_) {
      prefixBytes = null;
    }

    if (prefixBytes == null || prefixBytes.isEmpty) {
      return withReadableFile(
        entry.sourceUri,
        (file) => action(file, entry.sizeBytes),
      );
    }

    try {
      await tempFile.writeAsBytes(prefixBytes, flush: false);
      return await action(tempFile, entry.sizeBytes);
    } finally {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  Future<Uint8List> _readMetadataPrefixBytes(
    String sourceUri, {
    required int knownSizeBytes,
  }) async {
    final stream = await _safStream.readFileStream(
      sourceUri,
      bufferSize: _prefixChunkBytes,
    );
    final iterator = StreamIterator<Uint8List>(stream);
    final builder = BytesBuilder(copy: false);
    int? targetBytes;

    try {
      while (await iterator.moveNext()) {
        final chunk = iterator.current;
        if (chunk.isEmpty) continue;
        builder.add(chunk);

        if (targetBytes != null && builder.length < targetBytes) {
          continue;
        }
        final currentBytes = builder.toBytes();
        final estimated = _estimateNeededPrefixBytes(
          currentBytes,
          knownSizeBytes: knownSizeBytes,
        );
        if (estimated != null && (targetBytes == null || estimated > targetBytes)) {
          targetBytes = estimated;
        }
        if (targetBytes != null && currentBytes.length >= targetBytes) {
          break;
        }
      }
      return builder.takeBytes();
    } finally {
      await iterator.cancel();
    }
  }

  int? _estimateNeededPrefixBytes(
    Uint8List bytes, {
    required int knownSizeBytes,
  }) {
    if (bytes.length < 10) return null;

    var offset = 0;
    while (offset + 10 <= bytes.length) {
      if (bytes[offset] != 0x49 ||
          bytes[offset + 1] != 0x44 ||
          bytes[offset + 2] != 0x33 ||
          (bytes[offset + 6] & 0x80) != 0 ||
          (bytes[offset + 7] & 0x80) != 0 ||
          (bytes[offset + 8] & 0x80) != 0 ||
          (bytes[offset + 9] & 0x80) != 0) {
        break;
      }

      final tagSize =
          (bytes[offset + 9] & 0x7F) |
          ((bytes[offset + 8] & 0x7F) << 7) |
          ((bytes[offset + 7] & 0x7F) << 14) |
          ((bytes[offset + 6] & 0x7F) << 21);
      final hasFooter = bytes[offset + 3] == 4 && (bytes[offset + 5] & 0x10) != 0;
      final totalTag = 10 + tagSize + (hasFooter ? 10 : 0);
      if (totalTag <= 10 || offset + totalTag > _maxPrefixScanBytes) {
        return _maxPrefixScanBytes;
      }
      offset += totalTag;
    }

    final needed = offset > 0
        ? offset + _headerTailPaddingBytes
        : _noId3v2PrefixBytes;
    if (knownSizeBytes > 0 && knownSizeBytes < needed) {
      return knownSizeBytes;
    }
    return needed > _maxPrefixScanBytes ? _maxPrefixScanBytes : needed;
  }

  @override
  Future<String> resolvePlayableSource(String sourceUri) async {
    if (!sourceUri.startsWith('content://')) {
      return sourceUri;
    }
    final tempDir = await _getTempDir();
    final cacheDir = Directory(p.join(tempDir.path, 'pyure_playback_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final targetPath = p.join(
      cacheDir.path,
      '${stableHexHash(sourceUri)}.mp3',
    );
    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      final len = await targetFile.length();
      if (len > 0) {
        return targetPath;
      }
      try {
        await targetFile.delete();
      } catch (_) {}
    }

    final tempPart = File('$targetPath.part');
    try {
      await _safStream.copyToLocalFile(sourceUri, tempPart.path);
      if (!await tempPart.exists() || await tempPart.length() == 0) {
        throw const FileSystemException('Empty audio copy from SAF');
      }
      await tempPart.rename(targetPath);
      await _trimPlaybackCache(cacheDir, keepPath: targetPath);
      return targetPath;
    } catch (_) {
      if (await tempPart.exists()) {
        try {
          await tempPart.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _trimPlaybackCache(
    Directory cacheDir, {
    required String keepPath,
  }) async {
    try {
      final files = await cacheDir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      if (files.length <= _maxPlaybackCacheEntries) return;

      final withStats = <(File, DateTime)>[];
      for (final file in files) {
        if (p.equals(file.path, keepPath)) continue;
        final stat = await file.stat();
        withStats.add((file, stat.modified));
      }
      withStats.sort((a, b) => a.$2.compareTo(b.$2));

      final toRemove = files.length - _maxPlaybackCacheEntries;
      for (var i = 0; i < toRemove && i < withStats.length; i++) {
        await withStats[i].$1.delete();
      }
    } catch (_) {}
  }
}
