import 'package:material_ui/material_ui.dart';

import '../../../core/models/track.dart';
import '../../../core/preferences/app_preferences.dart';

@immutable
class PlayerState {
  const PlayerState({
    this.queue = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
    this.isLoadingTrack = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 0.85,
    this.repeatMode = PlaybackRepeatMode.off,
    this.ambientColor,
    this.errorMessage,
  });

  final List<Track> queue;
  final int currentIndex;
  final bool isPlaying;
  final bool isLoadingTrack;
  final Duration position;
  final Duration duration;
  final double volume;
  final PlaybackRepeatMode repeatMode;
  final Color? ambientColor;
  final String? errorMessage;

  Track? get currentTrack =>
      (currentIndex >= 0 && currentIndex < queue.length)
      ? queue[currentIndex]
      : null;

  bool get hasTrack => currentTrack != null;

  double get progressFraction {
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 0) return 0;
    return (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  PlayerState copyWith({
    List<Track>? queue,
    int? currentIndex,
    bool? isPlaying,
    bool? isLoadingTrack,
    Duration? position,
    Duration? duration,
    double? volume,
    PlaybackRepeatMode? repeatMode,
    Color? ambientColor,
    bool clearAmbientColor = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PlayerState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoadingTrack: isLoadingTrack ?? this.isLoadingTrack,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      repeatMode: repeatMode ?? this.repeatMode,
      ambientColor: clearAmbientColor
          ? null
          : (ambientColor ?? this.ambientColor),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
