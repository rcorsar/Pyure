import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/pyure_theme.dart';
import '../../library/presentation/albums_tab.dart';
import '../../library/presentation/library_provider.dart';
import '../../library/presentation/tracks_tab.dart';
import '../../player/presentation/mini_player.dart';
import '../../search/presentation/search_tab.dart';
import 'navigation_provider.dart';

/// Порог ширины экрана для переключения между мобильным и десктопным каркасом.
const double kDesktopBreakpoint = 720;

/// Адаптивный каркас приложения «Пюре».
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(navigationProvider);
    final libSummary = ref.watch(
      libraryProvider.select(
        (s) => (
          folderName: s.selectedFolder?.displayName,
          isScanning: s.isScanning,
        ),
      ),
    );

    final activePage = switch (currentTab) {
      AppTab.albums => const AlbumsTab(),
      AppTab.tracks => const TracksTab(),
      AppTab.search => const SearchTab(),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= kDesktopBreakpoint;

        if (isWide) {
          return Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _DesktopSidebar(
                        currentTab: currentTab,
                        folderName: libSummary.folderName,
                        isScanning: libSummary.isScanning,
                        onSelectTab: (index) => ref
                            .read(navigationProvider.notifier)
                            .selectIndex(index),
                        onPickFolder: () => ref
                            .read(libraryProvider.notifier)
                            .pickFolderAndScan(),
                        onRescan: () => ref
                            .read(libraryProvider.notifier)
                            .rescanLibrary(),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: activePage),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const MiniPlayerBar(isWide: true),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const _BrandTitle(),
            actions: [
              IconButton(
                tooltip: 'Выбрать папку с музыкой',
                icon: const Icon(Icons.folder_open_rounded),
                onPressed: libSummary.isScanning
                    ? null
                    : () => ref
                          .read(libraryProvider.notifier)
                          .pickFolderAndScan(),
              ),
              IconButton(
                tooltip: 'Обновить библиотеку',
                onPressed: libSummary.isScanning
                    ? null
                    : () => ref.read(libraryProvider.notifier).rescanLibrary(),
                icon: libSummary.isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(child: activePage),
              const Divider(height: 1),
              const MiniPlayerBar(isWide: false),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentTab.index,
            onDestinationSelected: (index) =>
                ref.read(navigationProvider.notifier).selectIndex(index),
            destinations: [
              for (final tab in AppTab.values)
                NavigationDestination(
                  icon: Icon(tab.icon),
                  selectedIcon: Icon(tab.selectedIcon),
                  label: tab.labelRu,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Pyure',
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.currentTab,
    required this.folderName,
    required this.isScanning,
    required this.onSelectTab,
    required this.onPickFolder,
    required this.onRescan,
  });

  final AppTab currentTab;
  final String? folderName;
  final bool isScanning;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onPickFolder;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pyure = context.pyureTheme;

    return Container(
      width: 232,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 22, 20, 12),
            child: _BrandTitle(),
          ),
          Expanded(
            child: NavigationRail(
              extended: true,
              minExtendedWidth: 232,
              selectedIndex: currentTab.index,
              onDestinationSelected: onSelectTab,
              destinations: [
                for (final tab in AppTab.values)
                  NavigationRailDestination(
                    icon: Icon(tab.icon),
                    selectedIcon: Icon(tab.selectedIcon),
                    label: Text(tab.labelRu),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  folderName ?? 'Папка не выбрана',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: pyure.subtleText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: isScanning ? null : onPickFolder,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Выбрать папку'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: isScanning ? null : onRescan,
                  icon: isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(isScanning ? 'Сканирование...' : 'Обновить'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
