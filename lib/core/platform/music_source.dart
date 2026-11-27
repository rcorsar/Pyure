import 'dart:io';
import 'dart:typed_data';

import 'android_saf_music_source.dart';
import 'windows_music_source.dart';

/// Выбранная пользователем корневая папка с музыкой.
class MusicFolderRef {
  const MusicFolderRef({
    required this.uri,
    required this.displayName,
    required this.isSafTree,
  });

  /// Путь в ФС на Windows или `content://` tree URI на Android.
  final String uri;
  final String displayName;
  final bool isSafTree;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicFolderRef &&
          runtimeType == other.runtimeType &&
          uri == other.uri &&
          displayName == other.displayName &&
          isSafTree == other.isSafTree;

  @override
  int get hashCode => Object.hash(uri, displayName, isSafTree);
}

/// Найденный при обходе папки MP3-файл (без предположений о `dart:io` пути).
class ScannedAudioEntry {
  const ScannedAudioEntry({
    required this.sourceUri,
    required this.fileName,
    required this.parentFolderName,
    required this.isRootLevel,
    required this.sizeBytes,
    required this.modifiedMs,
    this.siblingCoverUri,
  });

  /// Идентификатор файла: путь ФС (Windows) или `content://` URI (Android SAF).
  final String sourceUri;
  final String fileName;
  final String parentFolderName;

  /// `true`, если файл лежит непосредственно в корне выбранной папки («Без альбома»).
  final bool isRootLevel;

  final int sizeBytes;
  final int modifiedMs;

  /// URI соседнего `cover.jpg` / `folder.jpg`, если он найден в той же папке.
  final String? siblingCoverUri;
}

/// Платформозависимая абстракция доступа к локальной музыке.
abstract interface class MusicStorageSource {
  Future<MusicFolderRef?> pickMusicFolder();

  Future<bool> hasPersistedAccess(MusicFolderRef folder);

  Future<List<ScannedAudioEntry>> listMp3Entries(MusicFolderRef folder);

  /// Чтение сырых байтов файла (например, `cover.jpg` / `folder.jpg`).
  Future<Uint8List?> readBytes(String sourceUri);

  /// Предоставляет временный или нативный `File` для парсинга ID3-тегов.
  Future<T> withReadableFile<T>(
    String sourceUri,
    Future<T> Function(File file) action,
  );

  /// Предоставляет быстрый (может быть префиксным) локальный `File` с ID3/MPEG
  /// заголовками для ускоренного сканирования больших коллекций, а также
  /// известный полный размер исходного файла [fullFileSizeBytes].
  Future<T> withMetadataFile<T>(
    ScannedAudioEntry entry,
    Future<T> Function(File file, int fullFileSizeBytes) action,
  );

  /// Возвращает строку источника, пригодную для открытия в `media_kit` `Media(...)`:
  /// путь файла на Windows или кэшированный локальный путь для Android `content://`.
  Future<String> resolvePlayableSource(String sourceUri);
}

/// Создаёт реализацию [MusicStorageSource] для текущей платформы.
MusicStorageSource createMusicStorageSource() {
  if (Platform.isAndroid) {
    return AndroidSafMusicStorageSource();
  }
  return WindowsMusicStorageSource();
}
