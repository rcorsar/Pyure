import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

/// Абстракция над аудиодвижком (упрощает тестирование без нативного libmpv).
abstract interface class AudioPlaybackBackend {
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get completedStream;

  Future<void> open(String source, {required bool play});
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volumeZeroToOne);
  Future<void> dispose();
}

/// Реализация [AudioPlaybackBackend] поверх `media_kit`.
class MediaKitPlaybackBackend implements AudioPlaybackBackend {
  MediaKitPlaybackBackend()
    : _player = Player(
        configuration: const PlayerConfiguration(
          title: 'Pyure',
          bufferSize: 4 * 1024 * 1024,
        ),
      ) {
    if (Platform.isAndroid) {
      _androidAudioInit = _configureAndroidAudioPipeline();
    }
  }

  final Player _player;
  Future<void>? _androidAudioInit;

  Future<void> _configureAndroidAudioPipeline() async {
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        // Предпочитаем AudioTrack (с запасом буфера) поверх OpenSL ES, чтобы
        // Android 14-16 / GrapheneOS не останавливали аудиотракт при выключенном экране.
        await platform.setProperty('ao', 'audiotrack,opensles');
        await platform.setProperty('audio-buffer', '1.5');
      }
    } catch (_) {}
  }

  Future<void> _ensureAndroidConfigured() async {
    final init = _androidAudioInit;
    if (init != null) {
      await init;
    }
  }

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Future<void> open(String source, {required bool play}) async {
    await _ensureAndroidConfigured();
    return _player.open(Media(source), play: play);
  }

  @override
  Future<void> play() async {
    await _ensureAndroidConfigured();
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volumeZeroToOne) {
    final scaled = (volumeZeroToOne.clamp(0.0, 1.0)) * 100.0;
    return _player.setVolume(scaled);
  }

  @override
  Future<void> dispose() => _player.dispose();
}
