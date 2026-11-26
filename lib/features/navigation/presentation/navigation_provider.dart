import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Вкладки верхнего уровня в приложении «Пюре».
enum AppTab {
  albums(
    labelRu: 'Альбомы',
    icon: Icons.album_outlined,
    selectedIcon: Icons.album_rounded,
  ),
  tracks(
    labelRu: 'Треки',
    icon: Icons.music_note_outlined,
    selectedIcon: Icons.music_note_rounded,
  ),
  search(
    labelRu: 'Поиск',
    icon: Icons.search_rounded,
    selectedIcon: Icons.search_rounded,
  );

  const AppTab({
    required this.labelRu,
    required this.icon,
    required this.selectedIcon,
  });

  final String labelRu;
  final IconData icon;
  final IconData selectedIcon;
}

class NavigationNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.albums;

  void selectTab(AppTab tab) {
    state = tab;
  }

  void selectIndex(int index) {
    if (index >= 0 && index < AppTab.values.length) {
      state = AppTab.values[index];
    }
  }
}

final navigationProvider = NotifierProvider<NavigationNotifier, AppTab>(
  NavigationNotifier.new,
);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) {
    state = value;
  }

  void clear() {
    state = '';
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);
