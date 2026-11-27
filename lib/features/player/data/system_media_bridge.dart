import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:material_ui/material_ui.dart' show Color;

import '../../../core/models/track.dart';

/// Колбэки системных медиа-событий (шторка Android, гарнитура, кнопки Windows SMTC,
/// фокус аудио и отключение наушников).
class MediaControlCallbacks {
  const MediaControlCallbacks({
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    required this.onStop,
    required this.onBecomingNoisy,
    required this.onDuckChanged,
    required this.onPauseForInterruption,
    required this.onResumeFromInterruption,
  });

  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final Future<void> Function(Duration position) onSeek;
  final Future<void> Function() onStop;
  final Future<void> Function() onBecomingNoisy;
  final Future<void> Function(bool duck) onDuckChanged;
  final Future<void> Function() onPauseForInterruption;
  final Future<void> Function() onResumeFromInterruption;
}

/// Абстракция интеграции с системным медиаплеером ОС (Android / Windows SMTC).
abstract interface class SystemMediaBridge {
  void bindCallbacks(MediaControlCallbacks callbacks);

  Future<void> activateAudioSession();

  Future<void> updateTrackMetadata(Track? track, Duration duration);

  Future<void> updatePlaybackState({
    required bool hasTrack,
    required bool isPlaying,
    required bool isLoading,
    required Duration position,
  });

  Future<void> dispose();
}

/// Реализация [SystemMediaBridge] поверх `audio_service`, `audio_service_win`
/// и `audio_session`.
class AudioServiceMediaBridge implements SystemMediaBridge {
  AudioServiceMediaBridge._(this._handler, this._session);

  final _PyureAudioHandler _handler;
  final AudioSession? _session;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  MediaControlCallbacks? _callbacks;
  String? _lastMediaItemKey;
  Duration? _lastMediaItemDuration;
  bool _suppressedUntilPlayback = false;

  static Future<SystemMediaBridge> initialize() async {
    try {
      final handler = await AudioService.init(
        builder: _PyureAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.pyure.player.channel.audio',
          androidNotificationChannelName: 'Воспроизведение музыки',
          androidNotificationChannelDescription:
              'Управление воспроизведением Pyure в шторке и на экране блокировки',
          androidNotificationIcon: 'drawable/ic_stat_pyure',
          notificationColor: Color(0xFF18181B),
          artDownscaleWidth: 512,
          artDownscaleHeight: 512,
          androidNotificationOngoing: false,
          // Держим Foreground Service и WakeLock активными при паузе и смене трека,
          // чтобы Android 12–16 / GrapheneOS не замораживали процесс и не бросали
          // ForegroundServiceStartNotAllowedException при переходе на следующий трек.
          androidStopForegroundOnPause: false,
        ),
      );

      AudioSession? session;
      try {
        session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
      } catch (_) {
        session = null;
      }

      final bridge = AudioServiceMediaBridge._(handler, session);
      handler.onStopRequested = bridge._handleServiceStop;
      bridge._listenAudioSession();
      return bridge;
    } catch (_) {
      return NoopSystemMediaBridge();
    }
  }

  Future<void> _handleServiceStop() async {
    _suppressedUntilPlayback = true;
    await _callbacks?.onStop();
  }

  void _listenAudioSession() {
    final session = _session;
    if (session == null) return;

    _subscriptions.add(
      session.becomingNoisyEventStream.listen((_) {
        unawaited(_callbacks?.onBecomingNoisy());
      }),
    );

    _subscriptions.add(
      session.interruptionEventStream.listen((event) {
        final cb = _callbacks;
        if (cb == null) return;

        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              unawaited(cb.onDuckChanged(true));
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              unawaited(cb.onPauseForInterruption());
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              unawaited(cb.onDuckChanged(false));
            case AudioInterruptionType.pause:
              unawaited(cb.onResumeFromInterruption());
            case AudioInterruptionType.unknown:
              break;
          }
        }
      }),
    );
  }

  @override
  void bindCallbacks(MediaControlCallbacks callbacks) {
    _callbacks = callbacks;
    _handler.callbacks = callbacks;
  }

  @override
  Future<void> activateAudioSession() async {
    _suppressedUntilPlayback = false;
    try {
      await _session?.setActive(true);
    } catch (_) {}
  }

  @override
  Future<void> updateTrackMetadata(Track? track, Duration duration) async {
    try {
      if (track == null) {
        _lastMediaItemKey = null;
        _lastMediaItemDuration = null;
        _handler.setCurrentMediaItem(null);
        return;
      }

      final validDuration = duration > Duration.zero
          ? duration
          : (track.durationMs > 0
                ? Duration(milliseconds: track.durationMs)
                : null);

      if (_lastMediaItemKey == track.sourceUri &&
          _lastMediaItemDuration == validDuration) {
        return;
      }
      _lastMediaItemKey = track.sourceUri;
      _lastMediaItemDuration = validDuration;

      final artPath = track.artworkPath;
      final artUri = (artPath != null && artPath.isNotEmpty)
          ? Uri.file(artPath)
          : null;

      _handler.setCurrentMediaItem(
        MediaItem(
          id: track.sourceUri,
          title: track.title,
          artist: track.artist,
          album: track.album,
          duration: validDuration,
          artUri: artUri,
        ),
      );
    } catch (_) {}
  }

  @override
  Future<void> updatePlaybackState({
    required bool hasTrack,
    required bool isPlaying,
    required bool isLoading,
    required Duration position,
  }) async {
    try {
      if (isPlaying || isLoading) {
        _suppressedUntilPlayback = false;
      } else if (_suppressedUntilPlayback) {
        return;
      }

      final processingState = !hasTrack
          ? AudioProcessingState.idle
          : (isLoading && !isPlaying
                ? AudioProcessingState.loading
                : AudioProcessingState.ready);

      _handler.setCurrentPlaybackState(
        PlaybackState(
          controls: [
            MediaControl.skipToPrevious,
            if (isPlaying) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: processingState,
          playing: isPlaying,
          updatePosition: position,
          speed: isPlaying ? 1.0 : 0.0,
        ),
      );
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }
}

class _PyureAudioHandler extends BaseAudioHandler with SeekHandler {
  MediaControlCallbacks? callbacks;
  Future<void> Function()? onStopRequested;

  void setCurrentMediaItem(MediaItem? item) {
    mediaItem.add(item);
  }

  void setCurrentPlaybackState(PlaybackState state) {
    playbackState.add(state);
  }

  @override
  Future<void> play() => callbacks?.onPlay() ?? Future.value();

  @override
  Future<void> pause() => callbacks?.onPause() ?? Future.value();

  @override
  Future<void> stop() async {
    if (onStopRequested != null) {
      await onStopRequested!();
    } else {
      await callbacks?.onStop();
    }
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) =>
      callbacks?.onSeek(position) ?? Future.value();

  @override
  Future<void> skipToNext() => callbacks?.onNext() ?? Future.value();

  @override
  Future<void> skipToPrevious() => callbacks?.onPrevious() ?? Future.value();

  @override
  Future<void> onNotificationDeleted() => stop();

  @override
  Future<void> onTaskRemoved() async {
    final isPlaying = playbackState.valueOrNull?.playing ?? false;
    if (!isPlaying) {
      await stop();
    }
  }
}

/// Заглушка [SystemMediaBridge] для тестов или неподдерживаемых сред.
class NoopSystemMediaBridge implements SystemMediaBridge {
  @override
  void bindCallbacks(MediaControlCallbacks callbacks) {}

  @override
  Future<void> activateAudioSession() async {}

  @override
  Future<void> updateTrackMetadata(Track? track, Duration duration) async {}

  @override
  Future<void> updatePlaybackState({
    required bool hasTrack,
    required bool isPlaying,
    required bool isLoading,
    required Duration position,
  }) async {}

  @override
  Future<void> dispose() async {}
}
