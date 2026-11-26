import 'package:flutter/foundation.dart';

/// Метаданные индексированного MP3-трека из локальной БД.
@immutable
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumKey,
    required this.sourceUri,
    required this.folderUri,
    required this.parentFolderName,
    required this.durationMs,
    required this.addedAtEpochMs,
    required this.fileSizeBytes,
    required this.lastModifiedMs,
    this.trackNumber,
    this.artworkPath,
  });

  final int id;
  final String title;
  final String artist;
  final String album;
  final String albumKey;
  final int? trackNumber;

  /// Путь к файлу на Windows или SAF `content://` URI на Android.
  final String sourceUri;

  /// Корневая папка библиотеки (или дерево SAF).
  final String folderUri;

  final String parentFolderName;
  final int durationMs;
  final String? artworkPath;
  final int addedAtEpochMs;
  final int fileSizeBytes;
  final int lastModifiedMs;

  factory Track.fromMap(Map<String, Object?> map) {
    return Track(
      id: map['id'] as int,
      title: map['title'] as String,
      artist: map['artist'] as String,
      album: map['album'] as String,
      albumKey: map['album_key'] as String,
      trackNumber: map['track_number'] as int?,
      sourceUri: map['source_uri'] as String,
      folderUri: map['folder_uri'] as String,
      parentFolderName: map['parent_folder_name'] as String,
      durationMs: map['duration_ms'] as int,
      artworkPath: map['artwork_path'] as String?,
      addedAtEpochMs: map['added_at_epoch_ms'] as int,
      fileSizeBytes: map['file_size_bytes'] as int,
      lastModifiedMs: map['last_modified_ms'] as int,
    );
  }

  Map<String, Object?> toInsertMap() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'album_key': albumKey,
      'title_norm': title.toLowerCase(),
      'artist_norm': artist.toLowerCase(),
      'album_norm': album.toLowerCase(),
      'track_number': trackNumber,
      'source_uri': sourceUri,
      'folder_uri': folderUri,
      'parent_folder_name': parentFolderName,
      'duration_ms': durationMs,
      'artwork_path': artworkPath,
      'added_at_epoch_ms': addedAtEpochMs,
      'file_size_bytes': fileSizeBytes,
      'last_modified_ms': lastModifiedMs,
    };
  }

  Track copyWith({
    int? id,
    String? title,
    String? artist,
    String? album,
    String? albumKey,
    int? trackNumber,
    String? sourceUri,
    String? folderUri,
    String? parentFolderName,
    int? durationMs,
    String? artworkPath,
    int? addedAtEpochMs,
    int? fileSizeBytes,
    int? lastModifiedMs,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumKey: albumKey ?? this.albumKey,
      trackNumber: trackNumber ?? this.trackNumber,
      sourceUri: sourceUri ?? this.sourceUri,
      folderUri: folderUri ?? this.folderUri,
      parentFolderName: parentFolderName ?? this.parentFolderName,
      durationMs: durationMs ?? this.durationMs,
      artworkPath: artworkPath ?? this.artworkPath,
      addedAtEpochMs: addedAtEpochMs ?? this.addedAtEpochMs,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      lastModifiedMs: lastModifiedMs ?? this.lastModifiedMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          artist == other.artist &&
          album == other.album &&
          albumKey == other.albumKey &&
          trackNumber == other.trackNumber &&
          sourceUri == other.sourceUri &&
          folderUri == other.folderUri &&
          parentFolderName == other.parentFolderName &&
          durationMs == other.durationMs &&
          artworkPath == other.artworkPath &&
          addedAtEpochMs == other.addedAtEpochMs &&
          fileSizeBytes == other.fileSizeBytes &&
          lastModifiedMs == other.lastModifiedMs;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    artist,
    album,
    albumKey,
    trackNumber,
    sourceUri,
    folderUri,
    parentFolderName,
    durationMs,
    artworkPath,
    addedAtEpochMs,
    fileSizeBytes,
    lastModifiedMs,
  );
}
