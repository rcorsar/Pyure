import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/album_sort_order.dart';
import '../models/track_sort_order.dart';
import '../platform/music_source.dart';

/// Режим повтора воспроизведения.
enum PlaybackRepeatMode {
  off('Повтор выкл'),
  one('Повтор трека'),
  all('Повтор всех');

  const PlaybackRepeatMode(this.labelRu);

  final String labelRu;

  PlaybackRepeatMode next() {
    return switch (this) {
      PlaybackRepeatMode.off => PlaybackRepeatMode.all,
      PlaybackRepeatMode.all => PlaybackRepeatMode.one,
      PlaybackRepeatMode.one => PlaybackRepeatMode.off,
    };
  }
}

/// Хранилище пользовательских настроек и последнего состояния воспроизведения.
class AppPreferences {
  const AppPreferences(this._prefs);

  final SharedPreferences _prefs;

  static const _kFolderUri = 'selected_folder_uri';
  static const _kFolderName = 'selected_folder_name';
  static const _kFolderIsSaf = 'selected_folder_is_saf';
  static const _kLastTrackId = 'last_track_id';
  static const _kLastTrackUri = 'last_track_uri';
  static const _kLastPositionMs = 'last_position_ms';
  static const _kRepeatMode = 'repeat_mode';
  static const _kVolume = 'volume';
  static const _kSortOrder = 'track_sort_order';
  static const _kAlbumSortOrder = 'album_sort_order';

  MusicFolderRef? getSelectedFolder() {
    final uri = _prefs.getString(_kFolderUri);
    if (uri == null || uri.isEmpty) return null;
    final name = _prefs.getString(_kFolderName) ?? 'Музыка';
    final isSaf = _prefs.getBool(_kFolderIsSaf) ?? false;
    return MusicFolderRef(uri: uri, displayName: name, isSafTree: isSaf);
  }

  Future<void> setSelectedFolder(MusicFolderRef folder) async {
    await _prefs.setString(_kFolderUri, folder.uri);
    await _prefs.setString(_kFolderName, folder.displayName);
    await _prefs.setBool(_kFolderIsSaf, folder.isSafTree);
  }

  int? getLastTrackId() => _prefs.getInt(_kLastTrackId);

  String? getLastTrackUri() => _prefs.getString(_kLastTrackUri);

  int getLastPositionMs() => _prefs.getInt(_kLastPositionMs) ?? 0;

  Future<void> saveLastPlayback({
    required int trackId,
    required String sourceUri,
    required int positionMs,
  }) async {
    await _prefs.setInt(_kLastTrackId, trackId);
    await _prefs.setString(_kLastTrackUri, sourceUri);
    await _prefs.setInt(_kLastPositionMs, positionMs);
  }

  Future<void> saveLastPositionMs(int positionMs) async {
    await _prefs.setInt(_kLastPositionMs, positionMs);
  }

  PlaybackRepeatMode getRepeatMode() {
    final raw = _prefs.getString(_kRepeatMode);
    for (final mode in PlaybackRepeatMode.values) {
      if (mode.name == raw) return mode;
    }
    return PlaybackRepeatMode.off;
  }

  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    await _prefs.setString(_kRepeatMode, mode.name);
  }

  double getVolume() {
    final value = _prefs.getDouble(_kVolume);
    if (value == null) {
      return Platform.isAndroid || Platform.isIOS ? 1.0 : 0.85;
    }
    return value.clamp(0.0, 1.0);
  }

  Future<void> setVolume(double volume) async {
    await _prefs.setDouble(_kVolume, volume.clamp(0.0, 1.0));
  }

  TrackSortOrder getTrackSortOrder() {
    final raw = _prefs.getString(_kSortOrder);
    for (final order in TrackSortOrder.values) {
      if (order.name == raw) return order;
    }
    return TrackSortOrder.title;
  }

  Future<void> setTrackSortOrder(TrackSortOrder order) async {
    await _prefs.setString(_kSortOrder, order.name);
  }

  AlbumSortOrder getAlbumSortOrder() {
    final raw = _prefs.getString(_kAlbumSortOrder);
    for (final order in AlbumSortOrder.values) {
      if (order.name == raw) return order;
    }
    return AlbumSortOrder.artist;
  }

  Future<void> setAlbumSortOrder(AlbumSortOrder order) async {
    await _prefs.setString(_kAlbumSortOrder, order.name);
  }
}
