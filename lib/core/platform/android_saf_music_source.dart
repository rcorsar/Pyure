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

  static const List<String> _coverCandidates = [
    'cover.jpg',
    'folder.jpg',
    'cover.jpeg',
    'folder.jpeg',
    'cover.png',
    'folder.png',
  ];

  static const int _maxPlaybackCacheEntries = 4;

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
    await _walkSafDir(
      dirUri: folder.uri,
      folderName: '',
      isRootLevel: true,
      out: entries,
    );
    return entries;
  }

  Future<void> _cleanupStaleScanFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      await for (final entity in tempDir.list(followLinks: false)) {
        if (entity is File && p.basename(entity.path).startsWith('pyure_scan_')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _walkSafDir({
    required String dirUri,
    required String folderName,
    required bool isRootLevel,
    required List<ScannedAudioEntry> out,
  }) async {
    List<SafDocumentFile> children;
    try {
      children = await _safUtil.list(dirUri);
    } catch (_) {
      return;
    }

    final subDirs = <SafDocumentFile>[];
    final mp3Docs = <SafDocumentFile>[];
    String? siblingCoverUri;
    var bestCoverPriority = _coverCandidates.length;

    for (final doc in children) {
      final nameLower = doc.name.toLowerCase();
      if (doc.isDir) {
        if (nameLower.startsWith('.trashed') || nameLower == '.thumbnails') {
          continue;
        }
        subDirs.add(doc);
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

    for (final doc in mp3Docs) {
      out.add(
        ScannedAudioEntry(
          sourceUri: doc.uri,
          fileName: doc.name,
          parentFolderName: folderName,
          isRootLevel: isRootLevel,
          sizeBytes: doc.length < 0 ? 0 : doc.length,
          modifiedMs: doc.lastModified,
          siblingCoverUri: siblingCoverUri,
        ),
      );
    }

    for (final subDir in subDirs) {
      await _walkSafDir(
        dirUri: subDir.uri,
        folderName: subDir.name,
        isRootLevel: false,
        out: out,
      );
    }
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
    final tempDir = await getTemporaryDirectory();
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
  Future<String> resolvePlayableSource(String sourceUri) async {
    if (!sourceUri.startsWith('content://')) {
      return sourceUri;
    }
    final tempDir = await getTemporaryDirectory();
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
