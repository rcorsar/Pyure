import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/pyure_theme.dart';
import '../../../core/models/track_sort_order.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/smooth_scroll.dart';
import '../../player/presentation/player_provider.dart';
import 'library_provider.dart';
import 'widgets/track_tile.dart';

/// Вкладка «Треки»: полный список с сортировкой и запуском очереди.
class TracksTab extends ConsumerWidget {
  const TracksTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;
    final lib = ref.watch(
      libraryProvider.select(
        (s) => (
          tracks: s.tracks,
          sortOrder: s.sortOrder,
          isScanning: s.isScanning,
          selectedFolder: s.selectedFolder,
        ),
      ),
    );
    final playback = ref.watch(
      playerProvider.select(
        (s) => (uri: s.currentTrack?.sourceUri, isPlaying: s.isPlaying),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final hPad = isWide ? 28.0 : 16.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, isWide ? 24 : 16, hPad, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Треки',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (lib.tracks.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      formatTrackCount(lib.tracks.length),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: pyure.subtleText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final order in TrackSortOrder.values) ...[
                          ChoiceChip(
                            label: Text(order.labelRu),
                            selected: lib.sortOrder == order,
                            onSelected: (_) => ref
                                .read(libraryProvider.notifier)
                                .setSortOrder(order),
                          ),
                          if (order != TrackSortOrder.values.last)
                            const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  if (lib.isScanning) ...[
                    const SizedBox(height: 12),
                    const _TracksScanProgressBar(),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: lib.tracks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPad),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.queue_music_rounded,
                              size: 48,
                              color: pyure.subtleText,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Нет проиндексированных треков',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Выберите папку с музыкой и обновите библиотеку',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: pyure.subtleText,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : SmoothScrollArea(
                      thumbVisibility: isWide,
                      builder: (context, controller) {
                        return ListView.builder(
                          key: const PageStorageKey<String>('tracks_scroll'),
                          controller: controller,
                          scrollCacheExtent: const ScrollCacheExtent.pixels(600),
                          padding: EdgeInsets.fromLTRB(
                            hPad - 4,
                            8,
                            hPad - 4,
                            20,
                          ),
                          itemExtent: 68,
                          itemCount: lib.tracks.length,
                          itemBuilder: (context, index) {
                            final track = lib.tracks[index];
                            final isActive = playback.uri == track.sourceUri;
                            return TrackTile(
                              track: track,
                              isActive: isActive,
                              isPlaying: isActive && playback.isPlaying,
                              onTap: () => ref
                                  .read(playerProvider.notifier)
                                  .playQueue(lib.tracks, initialIndex: index),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _TracksScanProgressBar extends ConsumerWidget {
  const _TracksScanProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fraction = ref.watch(libraryProvider.select((s) => s.scanFraction));
    return LinearProgressIndicator(value: fraction);
  }
}
