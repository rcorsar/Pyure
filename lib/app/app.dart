import 'package:material_ui/material_ui.dart';

import '../features/navigation/presentation/app_shell.dart';
import 'theme/pyure_theme.dart';

/// Корневой виджет приложения Pyure.
class PyureApp extends StatelessWidget {
  const PyureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pyure',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: PyureTheme.dark(),
      theme: PyureTheme.dark(),
      home: const AppShell(),
    );
  }
}
