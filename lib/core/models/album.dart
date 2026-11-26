import 'package:flutter/foundation.dart';

/// Агрегированная модель альбома для сетки во вкладке «Альбомы».
@immutable
class Album {
  const Album({
    required this.key,
    required this.title,
    required this.artist,
    required this.trackCount,
    required this.folderUri,
    this.artworkPath,
  });

  final String key;
  final String title;
  final String artist;
  final int trackCount;
  final String folderUri;
  final String? artworkPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Album &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          title == other.title &&
          artist == other.artist &&
          trackCount == other.trackCount &&
          folderUri == other.folderUri &&
          artworkPath == other.artworkPath;

  @override
  int get hashCode =>
      Object.hash(key, title, artist, trackCount, folderUri, artworkPath);
}
