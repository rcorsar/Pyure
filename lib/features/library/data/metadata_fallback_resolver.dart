import '../../../core/models/album.dart';
import '../../../core/models/album_sort_order.dart';
import '../../../core/models/track.dart';
import '../../../core/platform/music_source.dart';
import '../../../core/utils/formatters.dart';

/// Результат нормализации метаданных одного MP3-файла.
class ResolvedMetadata {
  const ResolvedMetadata({
    required this.title,
    required this.artist,
    required this.album,
    required this.albumKey,
    this.trackNumber,
  });

  final String title;
  final String artist;
  final String album;
  final String albumKey;
  final int? trackNumber;
}

/// Фолбэк-резолвер для неполных или отсутствующих ID3-тегов.
abstract final class MetadataFallbackResolver {
  static const String noAlbumTitle = 'Без альбома';
  static const String noAlbumKey = '__no_album__';
  static const String unknownArtist = 'Неизвестный исполнитель';
  static const String variousArtists = 'Разные исполнители';

  static ResolvedMetadata resolve({
    required ScannedAudioEntry entry,
    String? tagTitle,
    String? tagArtist,
    String? tagAlbum,
    int? tagTrackNumber,
  }) {
    final cleanTagTitle = _cleanText(tagTitle);
    final cleanTagArtist = _cleanText(tagArtist);
    final cleanTagAlbum = _cleanText(tagAlbum);

    late final String resolvedTitle;
    late final String resolvedArtist;

    if (cleanTagTitle != null) {
      resolvedTitle = cleanTagTitle;
      resolvedArtist = cleanTagArtist ?? unknownArtist;
    } else {
      final parsed = _parseFileName(entry.fileName);
      resolvedTitle = parsed.title;
      resolvedArtist = cleanTagArtist ?? parsed.artist ?? unknownArtist;
    }

    final String resolvedAlbum;
    if (cleanTagAlbum != null) {
      resolvedAlbum = cleanTagAlbum;
    } else if (entry.isRootLevel || entry.parentFolderName.trim().isEmpty) {
      resolvedAlbum = noAlbumTitle;
    } else {
      resolvedAlbum = entry.parentFolderName.trim();
    }

    final albumKey = resolvedAlbum == noAlbumTitle
        ? noAlbumKey
        : 'album:${resolvedAlbum.toLowerCase()}';

    return ResolvedMetadata(
      title: resolvedTitle,
      artist: resolvedArtist,
      album: resolvedAlbum,
      albumKey: albumKey,
      trackNumber: tagTrackNumber,
    );
  }

  /// Разбирает имя файла без расширения: при наличии `Исполнитель - Трек`
  /// разделяет исполнителя и название.
  static ({String? artist, String title}) _parseFileName(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final trimmed = baseName.trim();

    if (trimmed.isEmpty) {
      return (artist: null, title: fileName);
    }

    for (final separator in const [' - ', ' – ', ' — ']) {
      final idx = trimmed.indexOf(separator);
      if (idx > 0) {
        final left = trimmed.substring(0, idx).trim();
        final right = trimmed.substring(idx + separator.length).trim();
        if (left.isNotEmpty && right.isNotEmpty) {
          return (artist: left, title: right);
        }
      }
    }

    return (artist: null, title: trimmed);
  }

  static String? _cleanText(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.replaceAll('\u0000', '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Группирует список треков в список альбомов для вкладки «Альбомы».
  static List<Album> aggregateAlbums(
    List<Track> tracks, {
    AlbumSortOrder sortOrder = AlbumSortOrder.artist,
  }) {
    final grouped = <String, List<Track>>{};
    for (final track in tracks) {
      grouped.putIfAbsent(track.albumKey, () => <Track>[]).add(track);
    }

    final albums = <Album>[];
    for (final entry in grouped.entries) {
      final albumTracks = entry.value;
      final first = albumTracks.first;

      final distinctArtists = <String>{};
      String? artwork;
      for (final track in albumTracks) {
        distinctArtists.add(track.artist);
        artwork ??= track.artworkPath;
      }

      final albumArtist = distinctArtists.length == 1
          ? distinctArtists.first
          : variousArtists;

      albums.add(
        Album(
          key: entry.key,
          title: first.album,
          artist: albumArtist,
          trackCount: albumTracks.length,
          folderUri: first.folderUri,
          artworkPath: artwork,
        ),
      );
    }

    return sortAlbums(albums, sortOrder);
  }

  /// Сортирует альбомы по выбранному порядку:
  /// сначала латиница A–Z, затем кириллица А–Я.
  static List<Album> sortAlbums(List<Album> albums, AlbumSortOrder sortOrder) {
    final sorted = List<Album>.from(albums);
    sorted.sort((a, b) {
      switch (sortOrder) {
        case AlbumSortOrder.artist:
          final artistCmp = compareLatinThenCyrillic(a.artist, b.artist);
          if (artistCmp != 0) return artistCmp;
          if (a.key == noAlbumKey && b.key != noAlbumKey) return 1;
          if (b.key == noAlbumKey && a.key != noAlbumKey) return -1;
          return compareLatinThenCyrillic(a.title, b.title);
        case AlbumSortOrder.title:
          if (a.key == noAlbumKey && b.key != noAlbumKey) return 1;
          if (b.key == noAlbumKey && a.key != noAlbumKey) return -1;
          final titleCmp = compareLatinThenCyrillic(a.title, b.title);
          if (titleCmp != 0) return titleCmp;
          return compareLatinThenCyrillic(a.artist, b.artist);
      }
    });
    return sorted;
  }
}
