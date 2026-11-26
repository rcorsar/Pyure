import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/pyure_theme.dart';
import '../../../core/models/album.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/backdrop_photo_background.dart';
import '../../../core/widgets/smooth_scroll.dart';
import '../../player/presentation/mini_player.dart';
import '../../player/presentation/player_provider.dart';
import 'library_provider.dart';
import 'widgets/artwork_box.dart';
import 'widgets/track_tile.dart';

/// Экран выбранного альбома с фоновой фотографией и списком треков.
class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({required this.album, super.key});

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;
    final tracksAsync = ref.watch(albumTracksProvider(album.key));
    final playback = ref.watch(
      playerProvider.select(
        (s) => (
          uri: s.currentTrack?.sourceUri,
          isPlaying: s.isPlaying,
          hasTrack: s.hasTrack,
        ),
      ),
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final hPad = isWide ? 28.0 : 16.0;

            return Scaffold(
              extendBodyBehindAppBar: true,
              appBar: AppBar(
                backgroundColor: const Color(0x660C0C0D),
                title: Text(album.title),
              ),
              body: Stack(
                fit: StackFit.expand,
                children: [
                  const BackdropPhotoBackground(),
                  SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        Expanded(
                          child: tracksAsync.when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (error, _) => Center(
                              child: Text('Ошибка загрузки треков: $error'),
                            ),
                            data: (tracks) {
                              return SmoothScrollArea(
                                thumbVisibility: isWide,
                                builder: (context, controller) {
                                  return CustomScrollView(
                                    controller: controller,
                                    slivers: [
                                  SliverPadding(
                                    padding: EdgeInsets.fromLTRB(
                                      hPad,
                                      12,
                                      hPad,
                                      20,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: isWide
                                          ? Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                ArtworkBox(
                                                  artworkPath:
                                                      album.artworkPath,
                                                  size: 180,
                                                  borderRadius: 16,
                                                  iconSize: 64,
                                                ),
                                                const SizedBox(width: 24),
                                                Expanded(
                                                  child: _AlbumHeaderMeta(
                                                    album: album,
                                                    trackCount: tracks.length,
                                                    onPlayAll: tracks.isEmpty
                                                        ? null
                                                        : () => ref
                                                              .read(
                                                                playerProvider
                                                                    .notifier,
                                                              )
                                                              .playQueue(
                                                                tracks,
                                                                initialIndex: 0,
                                                              ),
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Column(
                                              children: [
                                                Center(
                                                  child: ArtworkBox(
                                                    artworkPath:
                                                        album.artworkPath,
                                                    size: 200,
                                                    borderRadius: 18,
                                                    iconSize: 64,
                                                  ),
                                                ),
                                                const SizedBox(height: 18),
                                                _AlbumHeaderMeta(
                                                  album: album,
                                                  trackCount: tracks.length,
                                                  centered: true,
                                                  onPlayAll: tracks.isEmpty
                                                      ? null
                                                      : () => ref
                                                            .read(
                                                              playerProvider
                                                                  .notifier,
                                                            )
                                                            .playQueue(
                                                              tracks,
                                                              initialIndex: 0,
                                                            ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                  const SliverToBoxAdapter(
                                    child: Divider(height: 1),
                                  ),
                                  if (tracks.isEmpty)
                                    SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: Center(
                                        child: Text(
                                          'В этом альбоме нет треков',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: pyure.subtleText,
                                              ),
                                        ),
                                      ),
                                    )
                                  else
                                    SliverPadding(
                                      padding: EdgeInsets.fromLTRB(
                                        hPad - 4,
                                        8,
                                        hPad - 4,
                                        24,
                                      ),
                                      sliver: SliverList.builder(
                                        itemCount: tracks.length,
                                        itemBuilder: (context, index) {
                                          final track = tracks[index];
                                          final isActive =
                                              playback.uri == track.sourceUri;
                                          return RepaintBoundary(
                                            child: TrackTile(
                                              track: track,
                                              showAlbum: false,
                                              showTrackNumber: true,
                                              isActive: isActive,
                                              isPlaying:
                                                  isActive &&
                                                  playback.isPlaying,
                                              onTap: () => ref
                                                  .read(playerProvider.notifier)
                                                  .playQueue(
                                                    tracks,
                                                    initialIndex: index,
                                                  ),
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
                        if (playback.hasTrack) ...[
                          const Divider(height: 1),
                          MiniPlayerBar(isWide: isWide),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AlbumHeaderMeta extends StatelessWidget {
  const _AlbumHeaderMeta({
    required this.album,
    required this.trackCount,
    required this.onPlayAll,
    this.centered = false,
  });

  final Album album;
  final int trackCount;
  final VoidCallback? onPlayAll;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;

    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          album.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: centered ? TextAlign.center : TextAlign.start,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          '${album.artist} • ${formatTrackCount(trackCount)}',
          style: theme.textTheme.bodyMedium?.copyWith(color: pyure.subtleText),
          textAlign: centered ? TextAlign.center : TextAlign.start,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onPlayAll,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Слушать'),
        ),
      ],
    );
  }
}
