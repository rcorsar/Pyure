import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/pyure_theme.dart';

/// Квадратная скруглённая обложка альбома/трека с надёжным декодированием
/// без отложенного пропуска кадров при быстрой прокрутке и переходах.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;

    final Widget content;
    final path = artworkPath;
    if (path != null && path.isNotEmpty) {
      // Используем общий целевой размер 360 для плиток и экрана альбома,
      // чтобы они переиспользовали одну запись кэша без повторного декодирования.
      final cachePx = size != null && size!.isFinite
          ? (size! <= 64 ? 128 : (size! * 2).round().clamp(128, 512))
          : 360;
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
/// минуя [ScrollAwareImageProvider], чтобы плитки не застревали без картинки
/// при быстром скролле и возврате с дочерних экранов.
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
  bool _failed = false;
  bool _useFullResolutionFallback = false;
  bool _isResolvingSync = false;

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
    _resolve(inBuildPhase: true);
  }

  @override
  void didUpdateWidget(_DirectFileArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.cacheWidth != widget.cacheWidth) {
      _failed = false;
      _useFullResolutionFallback = false;
      _resolve(inBuildPhase: true);
    }
  }

  ImageProvider _buildProvider() {
    final base = FileImage(File(widget.path));
    if (_useFullResolutionFallback) {
      return base;
    }
    return ResizeImage(base, width: widget.cacheWidth);
  }

  void _resolve({bool inBuildPhase = false}) {
    final provider = _buildProvider();
    final newStream = provider.resolve(createLocalImageConfiguration(context));
    if (_imageStream?.key == newStream.key) {
      return;
    }
    if (_listener != null) {
      _imageStream?.removeListener(_listener!);
    }
    _imageStream = newStream;
    _isResolvingSync = inBuildPhase;
    try {
      if (_listener != null) {
        _imageStream!.addListener(_listener!);
      }
    } finally {
      _isResolvingSync = false;
    }
  }

  void _onImageFrame(ImageInfo info, bool synchronousCall) {
    if (!mounted) {
      info.dispose();
      return;
    }
    final oldInfo = _imageInfo;
    _imageInfo = info;
    if ((synchronousCall || _isResolvingSync) && oldInfo == null) {
      // Синхронное попадание в ImageCache до первой отрисовки — не нужен лишний setState.
      _failed = false;
      return;
    }
    setState(() {
      _failed = false;
    });
    if (oldInfo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => oldInfo.dispose());
    }
  }

  void _onImageError(Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    PaintingBinding.instance.imageCache.evict(_buildProvider());
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
      _resolve(inBuildPhase: _isResolvingSync);
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

  @override
  void dispose() {
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
      return _FallbackArtwork(iconSize: widget.iconSize);
    }
    final info = _imageInfo;
    if (info == null) {
      return const SizedBox.expand();
    }
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
            theme.colorScheme.surfaceContainerHigh,
            theme.colorScheme.surfaceContainerLow,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: iconSize,
          color: theme.colorScheme.primary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
