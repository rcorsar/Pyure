import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/pyure_theme.dart';
import '../../../core/models/album.dart';
import '../../../core/models/album_sort_order.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/smooth_scroll.dart';
import 'album_detail_screen.dart';
import 'library_provider.dart';
import 'widgets/artwork_box.dart';

/// Вкладка «Альбомы»: сетка плиток (3 колонки на Android, адаптивно на Windows).
class AlbumsTab extends ConsumerWidget {
  const AlbumsTab({super.key});

  void _openAlbum(BuildContext context, Album album) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AlbumDetailScreen(album: album),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;
    final lib = ref.watch(
      libraryProvider.select(
        (s) => (
          albums: s.albums,
          trackCount: s.tracks.length,
          albumSortOrder: s.albumSortOrder,
          selectedFolder: s.selectedFolder,
          isInitialLoading: s.isInitialLoading,
          isScanning: s.isScanning,
          errorMessage: s.errorMessage,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final hPad = isWide ? 28.0 : 16.0;

        return SmoothScrollArea(
          thumbVisibility: isWide,
          builder: (context, controller) {
            return CustomScrollView(
              key: const PageStorageKey<String>('albums_scroll'),
              controller: controller,
              scrollCacheExtent: const ScrollCacheExtent.pixels(600),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hPad, isWide ? 24 : 16, hPad, 14),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Альбомы',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lib.albums.isEmpty
                              ? (lib.selectedFolder?.displayName ??
                                    'Папка не выбрана')
                              : '${lib.albums.length} альб. • '
                                    '${formatTrackCount(lib.trackCount)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: pyure.subtleText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    if (lib.albums.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final order in AlbumSortOrder.values) ...[
                              ChoiceChip(
                                label: Text(order.labelRu),
                                selected: lib.albumSortOrder == order,
                                onSelected: (_) => ref
                                    .read(libraryProvider.notifier)
                                    .setAlbumSortOrder(order),
                              ),
                              if (order != AlbumSortOrder.values.last)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (lib.isScanning) ...[
                      const SizedBox(height: 14),
                      const _ScanProgressCard(),
                    ],
                    if (lib.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: lib.errorMessage!),
                    ],
                  ],
                ),
              ),
            ),
            if (lib.isInitialLoading && lib.albums.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (lib.albums.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.14,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Icon(
                                  Icons.album_rounded,
                                  size: 34,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                lib.selectedFolder == null
                                    ? 'Выберите папку с музыкой'
                                    : 'MP3-файлы не найдены',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                lib.selectedFolder == null
                                    ? 'Укажите папку с MP3-файлами (включая '
                                          'подпапки). Теги, обложки и кэш '
                                          'хранятся локально.'
                                    : 'В выбранной папке «${lib.selectedFolder!.displayName}» '
                                          'не найдено MP3-треков. Выберите другую папку '
                                          'или обновите библиотеку.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: pyure.subtleText,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: lib.isScanning
                                    ? null
                                    : () => ref
                                          .read(libraryProvider.notifier)
                                          .pickFolderAndScan(),
                                icon: const Icon(Icons.folder_open_rounded),
                                label: const Text('Выбрать папку с музыкой'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  isWide ? hPad : 14.0,
                  0,
                  isWide ? hPad : 14.0,
                  24,
                ),
                sliver: SliverGrid(
                  gridDelegate: isWide
                      ? const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 210,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.76,
                        )
                      : const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.68,
                        ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final album = lib.albums[index];
                      return _AlbumTile(
                        album: album,
                        compact: !isWide,
                        onTap: () => _openAlbum(context, album),
                      );
                    },
                    childCount: lib.albums.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
      },
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.album,
    required this.onTap,
    this.compact = false,
  });

  final Album album;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: compact
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: pyure.cardBorder),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 7 : 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ArtworkBox(
                artworkPath: album.artworkPath,
                borderRadius: compact ? 8 : 10,
                iconSize: compact ? 30 : 40,
              ),
              SizedBox(height: compact ? 7 : 10),
              Text(
                album.title,
                style:
                    (compact
                            ? theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12.5,
                                height: 1.15,
                              )
                            : theme.textTheme.bodyMedium)
                        ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                album.artist,
                style:
                    (compact
                            ? theme.textTheme.labelSmall?.copyWith(
                                fontSize: 11.0,
                                height: 1.15,
                              )
                            : theme.textTheme.bodySmall)
                        ?.copyWith(color: pyure.subtleText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanProgressCard extends ConsumerWidget {
  const _ScanProgressCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;
    final scan = ref.watch(
      libraryProvider.select(
        (s) => (
          total: s.scanTotal,
          processed: s.scanProcessed,
          currentFile: s.currentScanFile,
          fraction: s.scanFraction,
        ),
      ),
    );
    final label = scan.total > 0
        ? 'Сканирование: ${scan.processed} из ${scan.total}'
        : 'Поиск MP3-файлов...';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (scan.total > 0)
                  Text(
                    '${((scan.fraction ?? 0) * 100).round()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
            if (scan.currentFile.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                scan.currentFile,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: pyure.subtleText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: scan.fraction),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
