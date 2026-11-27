import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pyure_theme.dart';
import '../../../core/models/album.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/smooth_scroll.dart';
import '../../library/presentation/album_detail_screen.dart';
import '../../library/presentation/library_provider.dart';
import '../../library/presentation/widgets/artwork_box.dart';
import '../../library/presentation/widgets/track_tile.dart';
import '../../navigation/presentation/navigation_provider.dart';
import '../../player/presentation/player_provider.dart';

/// Вкладка «Поиск»: мгновенная фильтрация треков, исполнителей и альбомов из SQLite.
class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clearQuery() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).clear();
  }

  void _openAlbum(Album album) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AlbumDetailScreen(album: album),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;
    final query = ref.watch(searchQueryProvider);
    final trimmed = query.trim();
    final albums = ref.watch(libraryProvider.select((s) => s.albums));
    final playback = ref.watch(
      playerProvider.select(
        (s) => (uri: s.currentTrack?.sourceUri, isPlaying: s.isPlaying),
      ),
    );

    final matchingAlbums = trimmed.isEmpty
        ? const <Album>[]
        : albums
              .where((album) {
                final q = trimmed.toLowerCase();
                return album.title.toLowerCase().contains(q) ||
                    album.artist.toLowerCase().contains(q);
              })
              .toList(growable: false);

    final searchTracksAsync = ref.watch(searchResultsProvider(trimmed));

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final hPad = isWide ? 28.0 : 16.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, isWide ? 24 : 16, hPad, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Поиск',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    onChanged: (value) =>
                        ref.read(searchQueryProvider.notifier).setQuery(value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Трек, исполнителя или альбом...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              tooltip: 'Очистить',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _clearQuery,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: trimmed.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPad),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.manage_search_rounded,
                              size: 48,
                              color: pyure.subtleText,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Мгновенный поиск по базе данных',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Введите название трека, исполнителя или альбома',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: pyure.subtleText,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : searchTracksAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Center(
                        child: Text('Ошибка поиска: $err'),
                      ),
                      data: (tracks) {
                        if (matchingAlbums.isEmpty && tracks.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: hPad),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    size: 46,
                                    color: pyure.subtleText,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Ничего не найдено по запросу «$trimmed»',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return SmoothScrollArea(
                          thumbVisibility: isWide,
                          builder: (context, controller) {
                            return CustomScrollView(
                              controller: controller,
                              scrollCacheExtent:
                                  const ScrollCacheExtent.pixels(600),
                              slivers: [
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                    hPad,
                                    4,
                                    hPad,
                                    0,
                                  ),
                                  sliver: SliverToBoxAdapter(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (matchingAlbums.isNotEmpty) ...[
                                          Text(
                                            'Альбомы (${matchingAlbums.length})',
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                  color: pyure.subtleText,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 10),
                                          SizedBox(
                                            height: 168,
                                            child: ListView.separated(
                                              scrollDirection: Axis.horizontal,
                                              itemCount: matchingAlbums.length,
                                              separatorBuilder: (_, _) =>
                                                  const SizedBox(width: 12),
                                              itemBuilder: (context, index) {
                                                final album =
                                                    matchingAlbums[index];
                                                return SizedBox(
                                                  width: 126,
                                                  child: Card(
                                                    clipBehavior:
                                                        Clip.antiAlias,
                                                    child: InkWell(
                                                      onTap: () =>
                                                          _openAlbum(album),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              8,
                                                            ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            ArtworkBox(
                                                              artworkPath: album
                                                                  .artworkPath,
                                                              size: 98,
                                                              borderRadius: 8,
                                                              iconSize: 32,
                                                            ),
                                                            const SizedBox(
                                                              height: 6,
                                                            ),
                                                            Text(
                                                              album.title,
                                                              style: theme
                                                                  .textTheme
                                                                  .bodySmall
                                                                  ?.copyWith(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                            Text(
                                                              formatTrackCount(
                                                                album
                                                                    .trackCount,
                                                              ),
                                                              style: theme
                                                                  .textTheme
                                                                  .labelSmall
                                                                  ?.copyWith(
                                                                    color: pyure
                                                                        .subtleText,
                                                                  ),
                                                              maxLines: 1,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 18),
                                        ],
                                        if (tracks.isNotEmpty) ...[
                                          Text(
                                            'Треки (${tracks.length})',
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                  color: pyure.subtleText,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                if (tracks.isNotEmpty)
                                  SliverPadding(
                                    padding: EdgeInsets.fromLTRB(
                                      hPad,
                                      0,
                                      hPad,
                                      24,
                                    ),
                                    sliver: SliverFixedExtentList.builder(
                                      itemExtent: 68,
                                      itemCount: tracks.length,
                                      itemBuilder: (context, i) {
                                        final track = tracks[i];
                                        final isActive =
                                            playback.uri == track.sourceUri;
                                        return TrackTile(
                                          track: track,
                                          isActive: isActive,
                                          isPlaying:
                                              isActive && playback.isPlaying,
                                          onTap: () => ref
                                              .read(playerProvider.notifier)
                                              .playQueue(
                                                tracks,
                                                initialIndex: i,
                                              ),
                                        );
                                      },
                                    ),
                                  ),
                              ],
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
