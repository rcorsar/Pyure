import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/track.dart';
import '../../../core/preferences/app_preferences.dart';
import '../../library/presentation/library_provider.dart';
import '../data/audio_playback_backend.dart';
import '../data/system_media_bridge.dart';
import '../domain/playback_models.dart';

final audioPlaybackBackendProvider = Provider<AudioPlaybackBackend>((ref) {
  final backend = MediaKitPlaybackBackend();
  ref.onDispose(() {
    unawaited(backend.dispose());
  });
  return backend;
});

final systemMediaBridgeProvider = Provider<SystemMediaBridge>((ref) {
  final bridge = NoopSystemMediaBridge();
  ref.onDispose(() {
    unawaited(bridge.dispose());
  });
  return bridge;
});

class PlayerNotifier extends Notifier<PlayerState> {
  static const int _maxAmbientCacheSize = 32;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final LinkedHashMap<String, Color?> _ambientColorCache =
      LinkedHashMap<String, Color?>();

  int _lastPersistedPositionTimeMs = 0;
  int _lastUiPositionTimeMs = 0;
  bool _isTransitioning = false;
  bool _pausedByInterruption = false;

  AudioPlaybackBackend get _backend => ref.read(audioPlaybackBackendProvider);
  SystemMediaBridge get _mediaBridge => ref.read(systemMediaBridgeProvider);

  @override
  PlayerState build() {
    final prefs = ref.watch(appPreferencesProvider);
    final initialVolume = prefs.getVolume();
    final initialRepeat = prefs.getRepeatMode();

    _disposeSubscriptions();
    _bindSystemMediaCallbacks();
    _attachStreamListeners();
    ref.onDispose(_disposeSubscriptions);

    Future.microtask(() => _initializeAndRestore(initialVolume));

    return PlayerState(volume: initialVolume, repeatMode: initialRepeat);
  }

  void _disposeSubscriptions() {
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
  }

  void _bindSystemMediaCallbacks() {
    _mediaBridge.bindCallbacks(
      MediaControlCallbacks(
        onPlay: () async {
          if (!state.hasTrack) return;
          await _mediaBridge.activateAudioSession();
          await _backend.play();
        },
        onPause: () async {
          if (!state.hasTrack) return;
          await _backend.pause();
        },
        onNext: next,
        onPrevious: previous,
        onSeek: seek,
        onStop: () async {
          if (!state.hasTrack) return;
          await _backend.pause();
          await seek(Duration.zero);
        },
        onBecomingNoisy: () async {
          if (state.isPlaying) {
            await _backend.pause();
          }
        },
        onDuckChanged: (duck) async {
          final target = duck ? (state.volume * 0.25) : state.volume;
          await _backend.setVolume(target);
        },
        onPauseForInterruption: () async {
          if (state.isPlaying) {
            _pausedByInterruption = true;
            await _backend.pause();
          }
        },
        onResumeFromInterruption: () async {
          if (_pausedByInterruption) {
            _pausedByInterruption = false;
            await _mediaBridge.activateAudioSession();
            await _backend.play();
          }
        },
      ),
    );
  }

  void _attachStreamListeners() {
    _subscriptions.add(
      _backend.playingStream.listen((playing) {
        if (!ref.mounted) return;
        if (playing) {
          _pausedByInterruption = false;
          unawaited(_mediaBridge.activateAudioSession());
        }
        state = state.copyWith(isPlaying: playing);
        unawaited(_syncMediaBridgeState());
        if (!playing) {
          unawaited(_persistCurrentState());
        }
      }),
    );

    _subscriptions.add(
      _backend.positionStream.listen((pos) {
        if (!ref.mounted) return;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (pos == Duration.zero || nowMs - _lastUiPositionTimeMs >= 250) {
          _lastUiPositionTimeMs = nowMs;
          state = state.copyWith(position: pos);
        }
        if (state.isPlaying && nowMs - _lastPersistedPositionTimeMs >= 3000) {
          _lastPersistedPositionTimeMs = nowMs;
          unawaited(
            ref
                .read(appPreferencesProvider)
                .saveLastPositionMs(pos.inMilliseconds),
          );
        }
      }),
    );

    _subscriptions.add(
      _backend.durationStream.listen((dur) {
        if (!ref.mounted) return;
        if (dur > Duration.zero && dur != state.duration) {
          state = state.copyWith(duration: dur);
          unawaited(_mediaBridge.updateTrackMetadata(state.currentTrack, dur));
          unawaited(_syncMediaBridgeState());
        }
      }),
    );

    _subscriptions.add(
      _backend.completedStream.listen((completed) {
        if (!completed || !ref.mounted) return;
        unawaited(_onTrackCompleted());
      }),
    );
  }

  Future<void> _syncMediaBridgeState() {
    return _mediaBridge.updatePlaybackState(
      hasTrack: state.hasTrack,
      isPlaying: state.isPlaying,
      isLoading: state.isLoadingTrack,
      position: state.position,
    );
  }

  Future<void> _initializeAndRestore(double initialVolume) async {
    try {
      await _backend.setVolume(initialVolume);
    } catch (_) {}

    final prefs = ref.read(appPreferencesProvider);
    final lastTrackId = prefs.getLastTrackId();
    final lastTrackUri = prefs.getLastTrackUri();
    if (lastTrackId == null && lastTrackUri == null) return;

    try {
      final db = ref.read(appDatabaseProvider);
      final track = await db.findTrackByIdOrUri(
        id: lastTrackId,
        sourceUri: lastTrackUri,
      );
      if (track == null || !ref.mounted) return;

      final allTracks = await db.getAllTracks(
        sortOrder: prefs.getTrackSortOrder(),
      );
      if (!ref.mounted) return;

      final queue = allTracks.isNotEmpty
          ? List<Track>.unmodifiable(allTracks)
          : List<Track>.unmodifiable([track]);
      final initialIndex = queue.indexWhere(
        (t) => t.sourceUri == track.sourceUri,
      );
      final safeIndex = initialIndex >= 0 ? initialIndex : 0;

      final restoredPos = Duration(milliseconds: prefs.getLastPositionMs());
      final initialDuration = track.durationMs > 0
          ? Duration(milliseconds: track.durationMs)
          : Duration.zero;

      state = state.copyWith(
        queue: queue,
        currentIndex: safeIndex,
        position: restoredPos,
        duration: initialDuration,
      );

      unawaited(_updateAmbientColor(track.artworkPath));
      unawaited(_mediaBridge.updateTrackMetadata(track, initialDuration));
      unawaited(_syncMediaBridgeState());

      final playable = await ref
          .read(musicStorageSourceProvider)
          .resolvePlayableSource(track.sourceUri);
      if (!ref.mounted) return;

      await _backend.open(playable, play: false);
      if (restoredPos > Duration.zero) {
        await _backend.seek(restoredPos);
      }
    } catch (_) {
      // Если прошлый файл был удалён или доступ отозван, запускаемся чисто.
    }
  }

  Future<void> playQueue(List<Track> tracks, {int initialIndex = 0}) async {
    if (tracks.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, tracks.length - 1);

    state = state.copyWith(
      queue: List<Track>.unmodifiable(tracks),
      currentIndex: safeIndex,
      clearError: true,
    );

    await _loadAndPlayIndex(safeIndex, autoplay: true);
  }

  Future<void> togglePlayPause() async {
    if (!state.hasTrack) return;
    if (!state.isPlaying) {
      await _mediaBridge.activateAudioSession();
    }
    await _backend.playOrPause();
  }

  Future<void> seek(Duration position) async {
    if (!state.hasTrack) return;
    final clamped = position < Duration.zero
        ? Duration.zero
        : (state.duration > Duration.zero && position > state.duration
              ? state.duration
              : position);
    _lastUiPositionTimeMs = DateTime.now().millisecondsSinceEpoch;
    state = state.copyWith(position: clamped);
    await _backend.seek(clamped);
    await _syncMediaBridgeState();
    await ref
        .read(appPreferencesProvider)
        .saveLastPositionMs(clamped.inMilliseconds);
  }

  Future<void> next() async {
    if (state.queue.isEmpty || _isTransitioning) return;
    if (state.currentIndex + 1 < state.queue.length) {
      await _loadAndPlayIndex(state.currentIndex + 1, autoplay: true);
    } else if (state.repeatMode == PlaybackRepeatMode.all) {
      await _loadAndPlayIndex(0, autoplay: true);
    } else {
      await _backend.pause();
      await seek(Duration.zero);
    }
  }

  Future<void> previous() async {
    if (state.queue.isEmpty || _isTransitioning) return;
    if (state.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (state.currentIndex > 0) {
      await _loadAndPlayIndex(state.currentIndex - 1, autoplay: true);
    } else if (state.repeatMode == PlaybackRepeatMode.all) {
      await _loadAndPlayIndex(state.queue.length - 1, autoplay: true);
    } else {
      await seek(Duration.zero);
    }
  }

  Future<void> cycleRepeatMode() async {
    final nextMode = state.repeatMode.next();
    await ref.read(appPreferencesProvider).setRepeatMode(nextMode);
    if (!ref.mounted) return;
    state = state.copyWith(repeatMode: nextMode);
  }

  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    state = state.copyWith(volume: clamped);
    await _backend.setVolume(clamped);
    await ref.read(appPreferencesProvider).setVolume(clamped);
  }

  Future<void> _onTrackCompleted() async {
    if (_isTransitioning || state.queue.isEmpty) return;

    if (state.repeatMode == PlaybackRepeatMode.one) {
      _isTransitioning = true;
      try {
        await _backend.seek(Duration.zero);
        await _backend.play();
      } finally {
        _isTransitioning = false;
      }
      return;
    }

    await next();
  }

  Future<void> _loadAndPlayIndex(int index, {required bool autoplay}) async {
    if (index < 0 || index >= state.queue.length) return;
    _isTransitioning = true;
    final track = state.queue[index];
    final initialDur = track.durationMs > 0
        ? Duration(milliseconds: track.durationMs)
        : Duration.zero;

    _lastUiPositionTimeMs = 0;
    state = state.copyWith(
      currentIndex: index,
      isLoadingTrack: true,
      position: Duration.zero,
      duration: initialDur,
      clearError: true,
    );

    unawaited(_updateAmbientColor(track.artworkPath));
    unawaited(_mediaBridge.updateTrackMetadata(track, initialDur));
    unawaited(_syncMediaBridgeState());

    try {
      if (autoplay) {
        await _mediaBridge.activateAudioSession();
      }
      final playable = await ref
          .read(musicStorageSourceProvider)
          .resolvePlayableSource(track.sourceUri);
      if (!ref.mounted) return;

      await _backend.open(playable, play: autoplay);
      if (!ref.mounted) return;

      state = state.copyWith(isLoadingTrack: false);
      await _syncMediaBridgeState();
      await ref
          .read(appPreferencesProvider)
          .saveLastPlayback(
            trackId: track.id,
            sourceUri: track.sourceUri,
            positionMs: 0,
          );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isLoadingTrack: false,
        isPlaying: false,
        errorMessage: 'Не удалось воспроизвести «${track.title}»: $e',
      );
      await _syncMediaBridgeState();
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> _persistCurrentState() async {
    final track = state.currentTrack;
    if (track == null) return;
    await ref
        .read(appPreferencesProvider)
        .saveLastPlayback(
          trackId: track.id,
          sourceUri: track.sourceUri,
          positionMs: state.position.inMilliseconds,
        );
  }

  void _cacheAmbientColor(String key, Color? color) {
    if (_ambientColorCache.length >= _maxAmbientCacheSize &&
        !_ambientColorCache.containsKey(key)) {
      _ambientColorCache.remove(_ambientColorCache.keys.first);
    }
    _ambientColorCache[key] = color;
  }

  Future<void> _updateAmbientColor(String? artworkPath) async {
    if (artworkPath == null || artworkPath.isEmpty) {
      if (ref.mounted) {
        state = state.copyWith(clearAmbientColor: true);
      }
      return;
    }

    if (_ambientColorCache.containsKey(artworkPath)) {
      if (ref.mounted) {
        final cached = _ambientColorCache[artworkPath];
        state = cached == null
            ? state.copyWith(clearAmbientColor: true)
            : state.copyWith(ambientColor: cached);
      }
      return;
    }

    final file = File(artworkPath);
    if (!await file.exists()) {
      _cacheAmbientColor(artworkPath, null);
      return;
    }

    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: ResizeImage(FileImage(file), width: 64),
        brightness: Brightness.dark,
      );
      final glowColor = scheme.primary;
      _cacheAmbientColor(artworkPath, glowColor);
      if (ref.mounted && state.currentTrack?.artworkPath == artworkPath) {
        state = state.copyWith(ambientColor: glowColor);
      }
    } catch (_) {
      _cacheAmbientColor(artworkPath, null);
    }
  }
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);
