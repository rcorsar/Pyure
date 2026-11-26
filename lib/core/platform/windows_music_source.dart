import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'music_source.dart';

/// Реализация [MusicStorageSource] для Windows (и других десктопных ФС).
class WindowsMusicStorageSource implements MusicStorageSource {
  static const List<String> _coverCandidates = [
    'cover.jpg',
    'folder.jpg',
    'cover.jpeg',
    'folder.jpeg',
    'cover.png',
    'folder.png',
  ];

  @override
  Future<MusicFolderRef?> pickMusicFolder() async {
    final uri = await FilePicker.pickDirectory(
      dialogTitle: 'Выберите папку с музыкой',
    );
    if (uri == null) return null;

    final dirPath = uri.toFilePath(windows: Platform.isWindows);
    final normalized = p.normalize(dirPath);
    final name = p.basename(normalized).isEmpty
        ? normalized
        : p.basename(normalized);

    return MusicFolderRef(
      uri: normalized,
      displayName: name,
      isSafTree: false,
    );
  }

  @override
  Future<bool> hasPersistedAccess(MusicFolderRef folder) async {
    if (folder.isSafTree) return false;
    return Directory(folder.uri).exists();
  }

  @override
  Future<List<ScannedAudioEntry>> listMp3Entries(MusicFolderRef folder) async {
    final rootDir = Directory(folder.uri);
    if (!await rootDir.exists()) return const [];

    final entries = <ScannedAudioEntry>[];
    final normalizedRoot = p.normalize(rootDir.path);
    await _walkDirectory(
      dir: rootDir,
      normalizedRoot: normalizedRoot,
      out: entries,
    );
    return entries;
  }

  Future<void> _walkDirectory({
    required Directory dir,
    required String normalizedRoot,
    required List<ScannedAudioEntry> out,
  }) async {
    List<FileSystemEntity> children;
    try {
      children = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return;
    }

    final subDirs = <Directory>[];
    final mp3Files = <File>[];
    String? siblingCover;
    var bestCoverPriority = _coverCandidates.length;

    for (final entity in children) {
      if (entity is Directory) {
        subDirs.add(entity);
      } else if (entity is File) {
        final nameLower = p.basename(entity.path).toLowerCase();
        if (nameLower.endsWith('.mp3')) {
          mp3Files.add(entity);
        } else {
          final priority = _coverCandidates.indexOf(nameLower);
          if (priority != -1 && priority < bestCoverPriority) {
            bestCoverPriority = priority;
            siblingCover = entity.path;
          }
        }
      }
    }

    final normalizedDir = p.normalize(dir.path);
    final isRootLevel = p.equals(normalizedDir, normalizedRoot);
    final parentName = isRootLevel ? '' : p.basename(normalizedDir);

    for (final file in mp3Files) {
      try {
        final stat = await file.stat();
        out.add(
          ScannedAudioEntry(
            sourceUri: file.path,
            fileName: p.basename(file.path),
            parentFolderName: parentName,
            isRootLevel: isRootLevel,
            sizeBytes: stat.size,
            modifiedMs: stat.modified.millisecondsSinceEpoch,
            siblingCoverUri: siblingCover,
          ),
        );
      } on FileSystemException {
        // Пропускаем недоступные или удалённые во время обхода файлы.
      }
    }

    for (final subDir in subDirs) {
      await _walkDirectory(
        dir: subDir,
        normalizedRoot: normalizedRoot,
        out: out,
      );
    }
  }

  @override
  Future<Uint8List?> readBytes(String sourceUri) async {
    final file = File(sourceUri);
    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<T> withReadableFile<T>(
    String sourceUri,
    Future<T> Function(File file) action,
  ) {
    return action(File(sourceUri));
  }

  @override
  Future<String> resolvePlayableSource(String sourceUri) async {
    return sourceUri;
  }
}
