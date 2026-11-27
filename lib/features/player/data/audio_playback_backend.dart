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
  bool _hasOpenedInitialMedia = false;

  Future<void> _configureAndroidAudioPipeline() async {
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        // Держим один и тот же AudioTrack открытым с фиксированными параметрами
        // 48 kHz / stereo и тишиной в простое, чтобы Android 15–17 / GrapheneOS
        // не пересоздавали и не глушили аудиопоток при смене трека в фоне.
        await platform.setProperty('ao', 'audiotrack,opensles');
        await platform.setProperty('audio-stream-silence', 'yes');
        await platform.setProperty('gapless-audio', 'yes');
        await platform.setProperty('audio-samplerate', '48000');
        await platform.setProperty('audio-channels', 'stereo');
        await platform.setProperty('audio-buffer', '1.5');
        await platform.setProperty('cache', 'no');
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
    if (Platform.isAndroid && _hasOpenedInitialMedia) {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        // Меняем файл на лету через `loadfile replace` без `stop()`,
        // чтобы не разрушать активный foreground AudioTrack в фоне.
        await platform.command(['loadfile', source, 'replace']);
        await platform.setProperty('pause', play ? 'no' : 'yes');
        return;
      }
    }
    _hasOpenedInitialMedia = true;
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
