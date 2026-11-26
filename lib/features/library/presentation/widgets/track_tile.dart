import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/pyure_theme.dart';
import '../../../../core/models/track.dart';
import '../../../../core/utils/formatters.dart';
import 'artwork_box.dart';

/// Строка трека в списке библиотеки, альбоме или поиске.
class TrackTile extends StatelessWidget {
  const TrackTile({
    required this.track,
    required this.onTap,
    this.isActive = false,
    this.isPlaying = false,
    this.showAlbum = true,
    this.showTrackNumber = false,
    super.key,
  });

  final Track track;
  final VoidCallback onTap;
  final bool isActive;
  final bool isPlaying;
  final bool showAlbum;
  final bool showTrackNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;

    final subtitle = showAlbum
        ? '${track.artist} • ${track.album}'
        : track.artist;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: isActive
            ? BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.28),
                ),
              )
            : null,
        child: Row(
          children: [
            if (showTrackNumber) ...[
              SizedBox(
                width: 28,
                child: isActive
                    ? Icon(
                        isPlaying
                            ? Icons.graphic_eq_rounded
                            : Icons.pause_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      )
                    : Text(
                        track.trackNumber != null
                            ? '${track.trackNumber}'
                            : '•',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: pyure.subtleText,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
            ] else ...[
              Stack(
                alignment: Alignment.center,
                children: [
                  ArtworkBox(
                    artworkPath: track.artworkPath,
                    size: 46,
                    borderRadius: 9,
                    iconSize: 22,
                  ),
                  if (isActive)
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        isPlaying
                            ? Icons.graphic_eq_rounded
                            : Icons.play_arrow_rounded,
                        size: 22,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: pyure.subtleText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              track.durationMs > 0 ? formatDurationMs(track.durationMs) : '--:--',
              style: theme.textTheme.bodySmall?.copyWith(
                color: pyure.subtleText,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
