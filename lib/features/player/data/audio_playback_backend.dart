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
    _playerPlayingSub = _player.stream.playing.listen(_emitPlaying);
    if (Platform.isAndroid) {
      _androidAudioInit = _configureAndroidAudioPipeline();
    }
  }

  final Player _player;
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  StreamSubscription<bool>? _playerPlayingSub;
  Future<void>? _androidAudioInit;
  bool _hasOpenedInitialMedia = false;
  bool _isPlaying = false;

  void _emitPlaying(bool playing) {
    if (_playingController.isClosed) return;
    if (_isPlaying == playing) return;
    _isPlaying = playing;
    _playingController.add(playing);
  }

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
  Stream<bool> get playingStream => _playingController.stream;

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
        // Включаем обработку START_FILE / pause / eof-reached до loadfile,
        // чтобы media_kit синхронизировал playing/completed без вызова stop().
        platform.isPlayingStateChangeAllowed = play;
        await platform.command(['loadfile', source, 'replace']);
        await platform.setProperty('pause', play ? 'no' : 'yes');
        platform.state = platform.state.copyWith(
          playing: play,
          completed: false,
        );
        _emitPlaying(play);
        return;
      }
    }
    _hasOpenedInitialMedia = true;
    await _player.open(Media(source), play: play);
    _emitPlaying(play);
  }

  @override
  Future<void> play() async {
    await _ensureAndroidConfigured();
    await _player.play();
    _emitPlaying(true);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _emitPlaying(false);
  }

  @override
  Future<void> playOrPause() async {
    if (_isPlaying || _player.state.playing) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volumeZeroToOne) {
    final scaled = (volumeZeroToOne.clamp(0.0, 1.0)) * 100.0;
    return _player.setVolume(scaled);
  }

  @override
  Future<void> dispose() async {
    await _playerPlayingSub?.cancel();
    await _playingController.close();
    await _player.dispose();
  }
}
