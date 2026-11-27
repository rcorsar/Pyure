import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'music_source.dart';

/// Реализация [MusicStorageSource] для десктопных ОС (Windows и Linux).
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
    String? rawPath;
    try {
      final uri = await FilePicker.pickDirectory(
        dialogTitle: 'Выберите папку с музыкой',
      );
      if (uri == null) return null;
      rawPath = uri.scheme == 'file' || !uri.hasScheme
          ? uri.toFilePath(windows: Platform.isWindows)
          : uri.path;
    } catch (e) {
      if (!Platform.isLinux) rethrow;
      rawPath = await _pickLinuxDirectoryFallback();
      if (rawPath == null) return null;
    }

    final normalized = p.normalize(rawPath);
    final name = p.basename(normalized).isEmpty
        ? normalized
        : p.basename(normalized);

    return MusicFolderRef(
      uri: normalized,
      displayName: name,
      isSafTree: false,
    );
  }

  /// Запасной выбор папки на Linux, если `xdg-desktop-portal` недоступен.
  Future<String?> _pickLinuxDirectoryFallback() async {
    final home = Platform.environment['HOME'];
    final candidates = <({String exe, List<String> args})>[
      (
        exe: 'zenity',
        args: const [
          '--file-selection',
          '--directory',
          '--title=Выберите папку с музыкой',
        ],
      ),
      (
        exe: 'kdialog',
        args: [
          '--getexistingdirectory',
          if (home != null && home.isNotEmpty) home else '/',
          '--title',
          'Выберите папку с музыкой',
        ],
      ),
      (
        exe: 'yad',
        args: const [
          '--file',
          '--directory',
          '--title=Выберите папку с музыкой',
        ],
      ),
    ];

    var foundAnyTool = false;
    for (final candidate in candidates) {
      try {
        final result = await Process.run(
          candidate.exe,
          candidate.args,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        foundAnyTool = true;
        if (result.exitCode == 0) {
          final picked = (result.stdout as String).trim();
          if (picked.isNotEmpty) return picked;
        }
        return null;
      } on ProcessException {
        // Пробуем следующий диалог (zenity -> kdialog -> yad).
      }
    }

    if (!foundAnyTool) {
      throw const FileSystemException(
        'Не найден диалог выбора папки (установите xdg-desktop-portal или zenity/kdialog)',
      );
    }
    return null;
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
    final pendingDirs = <Directory>[rootDir];
    const concurrency = 8;

    while (pendingDirs.isNotEmpty) {
      final batchCount = pendingDirs.length < concurrency
          ? pendingDirs.length
          : concurrency;
      final batch = pendingDirs.sublist(0, batchCount);
      pendingDirs.removeRange(0, batchCount);

      final results = await Future.wait([
        for (final dir in batch)
          _scanSingleDirectory(dir: dir, normalizedRoot: normalizedRoot),
      ]);
      for (final res in results) {
        entries.addAll(res.entries);
        pendingDirs.addAll(res.subDirs);
      }
    }
    return entries;
  }

  Future<({List<ScannedAudioEntry> entries, List<Directory> subDirs})>
  _scanSingleDirectory({
    required Directory dir,
    required String normalizedRoot,
  }) async {
    List<FileSystemEntity> children;
    try {
      children = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return (entries: <ScannedAudioEntry>[], subDirs: <Directory>[]);
    }

    final subDirs = <Directory>[];
    final mp3Files = <File>[];
    String? siblingCover;
    var bestCoverPriority = _coverCandidates.length;

    for (final entity in children) {
      final baseLower = p.basename(entity.path).toLowerCase();
      if (entity is Directory) {
        if (baseLower.startsWith('.trash') ||
            baseLower == '.thumbnails' ||
            baseLower == 'lost+found') {
          continue;
        }
        subDirs.add(entity);
      } else if (entity is File) {
        if (!baseLower.startsWith('._') && baseLower.endsWith('.mp3')) {
          mp3Files.add(entity);
        } else {
          final priority = _coverCandidates.indexOf(baseLower);
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
    final out = <ScannedAudioEntry>[];

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

    return (entries: out, subDirs: subDirs);
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
  Future<T> withMetadataFile<T>(
    ScannedAudioEntry entry,
    Future<T> Function(File file, int fullFileSizeBytes) action,
  ) {
    return action(File(entry.sourceUri), entry.sizeBytes);
  }

  @override
  Future<String> resolvePlayableSource(String sourceUri) async {
    return sourceUri;
  }
}
