import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/pyure_theme.dart';

/// Ограничивает число одновременных декодирований новых обложек при быстрой
/// прокрутке длинных списков, чтобы не перегружать пул декодеров и GPU-текстуры
/// (и пропускать плитки, которые уже ушли за пределы экрана).
abstract final class _ArtworkDecodeQueue {
  static const int maxConcurrent = 6;
  static int _active = 0;
  static bool _pumping = false;
  static final Queue<VoidCallback> _waiters = Queue<VoidCallback>();

  static bool get canStartImmediately => _active < maxConcurrent;

  static void enqueue(VoidCallback onReady) {
    _waiters.addLast(onReady);
  }

  static void cancel(VoidCallback onReady) {
    _waiters.remove(onReady);
  }

  static void acquireImmediate() {
    _active++;
  }

  static void releaseAndPump() {
    if (_active > 0) {
      _active--;
    }
    if (_pumping) return;
    _pumping = true;
    try {
      while (_active < maxConcurrent && _waiters.isNotEmpty) {
        final next = _waiters.removeFirst();
        next();
      }
    } finally {
      _pumping = false;
    }
  }
}

/// Квадратная скруглённая обложка альбома/трека с надёжным декодированием,
/// ограничением очереди при быстром скролле и автовосстановлением при сбоях кэша.
class ArtworkBox extends StatelessWidget {
  const ArtworkBox({
    this.artworkPath,
    this.size,
    this.borderRadius = 12,
    this.iconSize = 28,
    super.key,
  });

  final String? artworkPath;
  final double? size;
  final double borderRadius;
  final double iconSize;

  /// Целевой размер декодирования в физических пикселях.
  ///
  /// Сетка альбомов (`size == null`) использует `256`, а крупная обложка
  /// внутри альбома/плеера (`size >= 180`) — `360..512`, чтобы они не
  /// разделяли один ключ кэша и не переполняли память при 400+ альбомах.
  static int resolveCacheWidth(double? size) {
    if (size != null && size.isFinite) {
      if (size <= 64) return 128;
      return (size * 2).round().clamp(360, 512);
    }
    return 256;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;

    final Widget content;
    final path = artworkPath;
    if (path != null && path.isNotEmpty) {
      final cachePx = resolveCacheWidth(size);
      content = _DirectFileArtwork(
        key: ValueKey<String>('$path@$cachePx'),
        path: path,
        cacheWidth: cachePx,
        iconSize: iconSize,
      );
    } else {
      content = _FallbackArtwork(iconSize: iconSize);
    }

    final box = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: pyure.cardBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: ColoredBox(
          color: theme.colorScheme.surfaceContainerHigh,
          child: SizedBox.expand(child: content),
        ),
      ),
    );

    if (size != null) {
      return SizedBox(width: size, height: size, child: box);
    }
    return AspectRatio(aspectRatio: 1, child: box);
  }
}

/// Загружает локальный файл обложки напрямую через [ImageProvider.resolve]
/// минуя [ScrollAwareImageProvider], контролируя конкурентные декодирования
/// и восстанавливаясь при зависании или сбое записи в [ImageCache].
class _DirectFileArtwork extends StatefulWidget {
  const _DirectFileArtwork({
    required this.path,
    required this.cacheWidth,
    required this.iconSize,
    super.key,
  });

  final String path;
  final int cacheWidth;
  final double iconSize;

  @override
  State<_DirectFileArtwork> createState() => _DirectFileArtworkState();
}

class _DirectFileArtworkState extends State<_DirectFileArtwork> {
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  ImageStreamListener? _listener;
  Timer? _watchdogTimer;
  VoidCallback? _queuedCallback;

  bool _failed = false;
  bool _useFullResolutionFallback = false;
  bool _isResolvingSync = false;
  bool _builtWithoutImage = false;
  bool _holdsDecodeSlot = false;
  bool _retriedAfterStall = false;

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener(
      _onImageFrame,
      onError: _onImageError,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleOrResolve(inBuildPhase: true);
  }

  @override
  void didUpdateWidget(_DirectFileArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.cacheWidth != widget.cacheWidth) {
      _cancelPendingWork();
      _failed = false;
      _useFullResolutionFallback = false;
      _retriedAfterStall = false;
      _scheduleOrResolve(inBuildPhase: true);
    }
  }

  ImageProvider _buildProvider() {
    final base = FileImage(File(widget.path));
    if (_useFullResolutionFallback) {
      return base;
    }
    return ResizeImage(base, width: widget.cacheWidth);
  }

  ImageCacheStatus? _peekSyncCacheStatus(ImageProvider provider) {
    ImageCacheStatus? status;
    final config = createLocalImageConfiguration(context);
    provider.obtainKey(config).then<void>((Object key) {
      status = PaintingBinding.instance.imageCache.statusForKey(key);
    });
    return status;
  }

  void _scheduleOrResolve({required bool inBuildPhase}) {
    if (!mounted) return;
    final provider = _buildProvider();
    final status = _peekSyncCacheStatus(provider);
    final isAlreadyTracked = status != null && status.tracked;

    if (isAlreadyTracked) {
      _resolve(provider, inBuildPhase: inBuildPhase);
      return;
    }

    if (_holdsDecodeSlot || _ArtworkDecodeQueue.canStartImmediately) {
      if (!_holdsDecodeSlot) {
        _ArtworkDecodeQueue.acquireImmediate();
        _holdsDecodeSlot = true;
      }
      _resolve(provider, inBuildPhase: inBuildPhase);
      return;
    }

    if (_queuedCallback != null) return;
    late final VoidCallback onReady;
    onReady = () {
      _queuedCallback = null;
      if (!mounted) {
        return;
      }
      final nextProvider = _buildProvider();
      final nextStatus = _peekSyncCacheStatus(nextProvider);
      if (nextStatus == null || !nextStatus.tracked) {
        _ArtworkDecodeQueue.acquireImmediate();
        _holdsDecodeSlot = true;
      }
      _resolve(nextProvider, inBuildPhase: false);
    };
    _queuedCallback = onReady;
    _ArtworkDecodeQueue.enqueue(onReady);
  }

  void _resolve(ImageProvider provider, {required bool inBuildPhase}) {
    final newStream = provider.resolve(createLocalImageConfiguration(context));
    if (_imageStream?.key == newStream.key) {
      _releaseDecodeSlot();
      return;
    }
    if (_listener != null) {
      _imageStream?.removeListener(_listener!);
    }
    _imageStream = newStream;
    _startWatchdog(provider);
    _isResolvingSync = inBuildPhase;
    try {
      if (_listener != null) {
        _imageStream!.addListener(_listener!);
      }
    } finally {
      _isResolvingSync = false;
    }
  }

  void _evictProviderSync(ImageProvider provider) {
    provider.obtainKey(createLocalImageConfiguration(context)).then<void>((
      Object key,
    ) {
      PaintingBinding.instance.imageCache.evict(key);
    });
  }

  void _startWatchdog(ImageProvider provider) {
    _watchdogTimer?.cancel();
    if (_imageInfo != null || _failed) return;
    _watchdogTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted || _imageInfo != null || _failed) return;
      _releaseDecodeSlot();
      _evictProviderSync(provider);
      if (!_useFullResolutionFallback || !_retriedAfterStall) {
        _retriedAfterStall = true;
        if (mounted) {
          setState(() {
            _useFullResolutionFallback = true;
          });
        }
        _scheduleOrResolve(inBuildPhase: false);
      } else {
        setState(() {
          _failed = true;
        });
      }
    });
  }

  void _onImageFrame(ImageInfo info, bool synchronousCall) {
    _watchdogTimer?.cancel();
    _releaseDecodeSlot();
    if (!mounted) {
      info.dispose();
      return;
    }
    final oldInfo = _imageInfo;
    _imageInfo = info;
    _failed = false;
    if (!_builtWithoutImage &&
        (synchronousCall || _isResolvingSync) &&
        oldInfo == null) {
      // Синхронное попадание в ImageCache до первой отрисовки — не нужен лишний setState.
      return;
    }
    setState(() {});
    if (oldInfo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => oldInfo.dispose());
    }
  }

  void _onImageError(Object error, StackTrace? stackTrace) {
    _watchdogTimer?.cancel();
    _releaseDecodeSlot();
    if (!mounted) return;
    _evictProviderSync(_buildProvider());
    final canRetryFullResolution =
        !_useFullResolutionFallback && error is! FileSystemException;
    if (canRetryFullResolution) {
      // Если ResizeImage не смог декодировать существующий файл,
      // пробуем декодировать исходный файл без ресайза.
      if (_isResolvingSync) {
        _useFullResolutionFallback = true;
      } else {
        setState(() {
          _useFullResolutionFallback = true;
        });
      }
      _scheduleOrResolve(inBuildPhase: _isResolvingSync);
      return;
    }
    if (_isResolvingSync) {
      _failed = true;
    } else {
      setState(() {
        _failed = true;
      });
    }
  }

  void _releaseDecodeSlot() {
    if (_holdsDecodeSlot) {
      _holdsDecodeSlot = false;
      _ArtworkDecodeQueue.releaseAndPump();
    }
  }

  void _cancelPendingWork() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    final queued = _queuedCallback;
    if (queued != null) {
      _queuedCallback = null;
      _ArtworkDecodeQueue.cancel(queued);
    }
    _releaseDecodeSlot();
  }

  @override
  void dispose() {
    _cancelPendingWork();
    if (_listener != null) {
      _imageStream?.removeListener(_listener!);
    }
    _imageInfo?.dispose();
    _imageInfo = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      _builtWithoutImage = false;
      return _FallbackArtwork(iconSize: widget.iconSize);
    }
    final info = _imageInfo;
    if (info == null) {
      _builtWithoutImage = true;
      return const SizedBox.expand();
    }
    _builtWithoutImage = false;
    return RawImage(
      image: info.image,
      scale: info.scale,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
    );
  }
}

class _FallbackArtwork extends StatelessWidget {
  const _FallbackArtwork({required this.iconSize});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.surfaceContainer,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: iconSize,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
