import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/pyure_theme.dart';
import '../../../core/models/album.dart';
import '../../../core/preferences/app_preferences.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/backdrop_photo_background.dart';
import '../../library/presentation/album_detail_screen.dart';
import '../../library/presentation/library_provider.dart';
import '../../library/presentation/widgets/artwork_box.dart';
import 'player_provider.dart';

/// Открывает раскрывающийся полноэкранный плеер.
Future<void> showPyureNowPlayingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    backgroundColor: Colors.transparent,
    builder: (_) => const NowPlayingSheet(),
  );
}

/// Полноэкранный плеер с фоновой фотографией и управлением воспроизведением.
class NowPlayingSheet extends ConsumerWidget {
  const NowPlayingSheet({super.key});

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
          repeatMode: s.repeatMode,
          errorMessage: s.errorMessage,
        ),
      ),
    );
    final track = snap.track;

    if (track == null) {
      return const SizedBox.shrink();
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: DecoratedBox(
            decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const BackdropPhotoBackground(
                  topScrimAlpha: 0.52,
                  middleScrimAlpha: 0.72,
                  bottomScrimAlpha: 0.86,
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 720;
                    final isCompactHeight = constraints.maxHeight < 660;
                    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
                    final artSize = isCompactHeight
                        ? (constraints.maxHeight * 0.28).clamp(110.0, 180.0)
                        : (constraints.maxHeight * 0.34).clamp(160.0, 320.0);

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            isWide ? 32 : 24,
                            12,
                            isWide ? 32 : 24,
                            28 + bottomInset,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: pyure.subtleText.withValues(
                                    alpha: 0.45,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Свернуть',
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    icon: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          'СЕЙЧАС ИГРАЕТ',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: pyure.subtleText,
                                                letterSpacing: 1.1,
                                              ),
                                        ),
                                        Text(
                                          track.album,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 48),
                                ],
                              ),
                              const SizedBox(height: 20),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.65,
                                      ),
                                      blurRadius: 32,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: ArtworkBox(
                                  artworkPath: track.artworkPath,
                                  size: artSize,
                                  borderRadius: 22,
                                  iconSize: 72,
                                ),
                              ),
                              const SizedBox(height: 26),
                              Text(
                                track.title,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                track.artist,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: pyure.subtleText,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (snap.errorMessage != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  snap.errorMessage!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              const SizedBox(height: 20),
                              const _SeekSliderSection(),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton(
                                    tooltip: 'На альбом',
                                    onPressed: () {
                                      final albums =
                                          ref.read(libraryProvider).albums;
                                      Album? targetAlbum;
                                      for (final item in albums) {
                                        if (item.key == track.albumKey) {
                                          targetAlbum = item;
                                          break;
                                        }
                                      }
                                      final resolvedAlbum =
                                          targetAlbum ??
                                          Album(
                                            key: track.albumKey,
                                            title: track.album,
                                            artist: track.artist,
                                            trackCount: 1,
                                            folderUri: track.folderUri,
                                            artworkPath: track.artworkPath,
                                          );
                                      final navigator = Navigator.of(context);
                                      navigator.popUntil(
                                        (route) => route.isFirst,
                                      );
                                      navigator.push<void>(
                                        MaterialPageRoute<void>(
                                          builder: (_) => AlbumDetailScreen(
                                            album: resolvedAlbum,
                                          ),
                                        ),
                                      );
                                    },
                                    iconSize: 26,
                                    icon: Icon(
                                      Icons.album_rounded,
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.88),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Предыдущий трек',
                                    iconSize: 34,
                                    onPressed: () => ref
                                        .read(playerProvider.notifier)
                                        .previous(),
                                    icon: const Icon(
                                      Icons.skip_previous_rounded,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 68,
                                    height: 68,
                                    child: IconButton.filled(
                                      tooltip: snap.isPlaying
                                          ? 'Пауза'
                                          : 'Воспроизвести',
                                      iconSize: 36,
                                      onPressed: () => ref
                                          .read(playerProvider.notifier)
                                          .togglePlayPause(),
                                      icon: snap.isLoading
                                          ? SizedBox(
                                              width: 26,
                                              height: 26,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color:
                                                    theme.colorScheme.onPrimary,
                                              ),
                                            )
                                          : Icon(
                                              snap.isPlaying
                                                  ? Icons.pause_rounded
                                                  : Icons.play_arrow_rounded,
                                            ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Следующий трек',
                                    iconSize: 34,
                                    onPressed: () => ref
                                        .read(playerProvider.notifier)
                                        .next(),
                                    icon: const Icon(Icons.skip_next_rounded),
                                  ),
                                  IconButton(
                                    tooltip: snap.repeatMode.labelRu,
                                    onPressed: () => ref
                                        .read(playerProvider.notifier)
                                        .cycleRepeatMode(),
                                    icon: Icon(
                                      snap.repeatMode == PlaybackRepeatMode.one
                                          ? Icons.repeat_one_rounded
                                          : Icons.repeat_rounded,
                                      color:
                                          snap.repeatMode !=
                                              PlaybackRepeatMode.off
                                          ? theme.colorScheme.primary
                                          : pyure.subtleText,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Icon(
                                    snap.volume == 0
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_down_rounded,
                                    size: 20,
                                    color: pyure.subtleText,
                                  ),
                                  Expanded(
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        trackHeight: 3,
                                        thumbShape:
                                            const RoundSliderThumbShape(
                                              enabledThumbRadius: 6,
                                            ),
                                      ),
                                      child: Slider(
                                        value: snap.volume,
                                        onChanged: (v) => ref
                                            .read(playerProvider.notifier)
                                            .setVolume(v),
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.volume_up_rounded,
                                    size: 20,
                                    color: pyure.subtleText,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeekSliderSection extends ConsumerStatefulWidget {
  const _SeekSliderSection();

  @override
  ConsumerState<_SeekSliderSection> createState() => _SeekSliderSectionState();
}

class _SeekSliderSectionState extends ConsumerState<_SeekSliderSection> {
  double? _scrubValueMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;
    final timing = ref.watch(
      playerProvider.select(
        (s) => (position: s.position, duration: s.duration),
      ),
    );

    final durationMs = timing.duration.inMilliseconds;
    final sliderMax = durationMs > 0 ? durationMs.toDouble() : 1.0;
    final currentPosMs =
        _scrubValueMs ??
        timing.position.inMilliseconds.toDouble().clamp(0.0, sliderMax);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            min: 0,
            max: sliderMax,
            value: currentPosMs,
            onChanged: durationMs > 0
                ? (v) => setState(() => _scrubValueMs = v)
                : null,
            onChangeEnd: durationMs > 0
                ? (v) {
                    setState(() => _scrubValueMs = null);
                    ref
                        .read(playerProvider.notifier)
                        .seek(Duration(milliseconds: v.round()));
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDurationMs(currentPosMs.round()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: pyure.subtleText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                durationMs > 0 ? formatDurationMs(durationMs) : '--:--',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: pyure.subtleText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
