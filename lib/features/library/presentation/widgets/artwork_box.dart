import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/pyure_theme.dart';

/// Квадратная скруглённая обложка альбома/трека с мягкой заглушкой.
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
    if (artworkPath != null && artworkPath!.isNotEmpty) {
      final cachePx = size != null && size!.isFinite
          ? (size! * 2).round().clamp(96, 512)
          : 320;
      content = Image.file(
        File(artworkPath!),
        fit: BoxFit.cover,
        cacheWidth: cachePx,
        filterQuality: FilterQuality.low,
        errorBuilder: (context, error, stackTrace) =>
            _FallbackArtwork(iconSize: iconSize),
      );
    } else {
      content = _FallbackArtwork(iconSize: iconSize);
    }

    final box = RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: pyure.cardBorder),
          ),
          child: content,
        ),
      ),
    );

    if (size != null) {
      return SizedBox(width: size, height: size, child: box);
    }
    return AspectRatio(aspectRatio: 1, child: box);
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
