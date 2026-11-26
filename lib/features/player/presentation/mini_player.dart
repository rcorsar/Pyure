import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/pyure_theme.dart';
import '../../library/presentation/widgets/artwork_box.dart';
import 'now_playing_sheet.dart';
import 'player_provider.dart';

/// Закреплённый мини-плеер внизу экрана с градиентом в тон обложки и быстрым управлением.
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({required this.isWide, super.key});

  final bool isWide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;
    final snap = ref.watch(
      playerProvider.select(
        (s) => (
          track: s.currentTrack,
          isPlaying: s.isPlaying,
          isLoading: s.isLoadingTrack,
          volume: s.volume,
          ambientColor: s.ambientColor,
        ),
      ),
    );
    final track = snap.track;

    final glowColor =
        snap.ambientColor?.withValues(alpha: 0.22) ?? pyure.playerGlowColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _MiniPlayerProgressBar(),
        InkWell(
          onTap: track == null
              ? null
              : () => showPyureNowPlayingSheet(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            height: 70,
            padding: EdgeInsets.symmetric(horizontal: isWide ? 20 : 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  pyure.miniPlayerSurface,
                  Color.alphaBlend(glowColor, pyure.miniPlayerSurface),
                ],
              ),
            ),
            child: Row(
              children: [
                ArtworkBox(
                  artworkPath: track?.artworkPath,
                  size: 46,
                  borderRadius: 10,
                  iconSize: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track?.title ?? 'Ничего не воспроизводится',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track?.artist ?? 'Выберите трек из библиотеки',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: pyure.subtleText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isWide && track != null) ...[
                  Icon(
                    snap.volume == 0
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    size: 18,
                    color: pyure.subtleText,
                  ),
                  SizedBox(
                    width: 110,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.5,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        value: snap.volume,
                        onChanged: (v) =>
                            ref.read(playerProvider.notifier).setVolume(v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (isWide)
                  IconButton(
                    tooltip: 'Предыдущий трек',
                    onPressed: track == null
                        ? null
                        : () => ref.read(playerProvider.notifier).previous(),
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                IconButton.filledTonal(
                  tooltip: snap.isPlaying ? 'Пауза' : 'Воспроизвести',
                  onPressed: track == null
                      ? null
                      : () =>
                            ref.read(playerProvider.notifier).togglePlayPause(),
                  icon: snap.isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          snap.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                ),
                IconButton(
                  tooltip: 'Следующий трек',
                  onPressed: track == null
                      ? null
                      : () => ref.read(playerProvider.notifier).next(),
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniPlayerProgressBar extends ConsumerWidget {
  const _MiniPlayerProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(
      playerProvider.select(
        (s) => s.hasTrack ? s.progressFraction : 0.0,
      ),
    );

    return RepaintBoundary(
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 2.5,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
      ),
    );
  }
}
