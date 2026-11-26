import 'package:material_ui/material_ui.dart';

/// Дополнительные токены темы Pyure (включая цвет фонового свечения от обложки).
@immutable
class PyureThemeExtension extends ThemeExtension<PyureThemeExtension> {
  const PyureThemeExtension({
    required this.playerGlowColor,
    required this.miniPlayerSurface,
    required this.cardBorder,
    required this.subtleText,
    required this.accentSilver,
  });

  /// Мягкая подсветка мини- и полноэкранного плеера (из обложки трека).
  final Color playerGlowColor;
  final Color miniPlayerSurface;
  final Color cardBorder;
  final Color subtleText;
  final Color accentSilver;

  @override
  PyureThemeExtension copyWith({
    Color? playerGlowColor,
    Color? miniPlayerSurface,
    Color? cardBorder,
    Color? subtleText,
    Color? accentSilver,
  }) {
    return PyureThemeExtension(
      playerGlowColor: playerGlowColor ?? this.playerGlowColor,
      miniPlayerSurface: miniPlayerSurface ?? this.miniPlayerSurface,
      cardBorder: cardBorder ?? this.cardBorder,
      subtleText: subtleText ?? this.subtleText,
      accentSilver: accentSilver ?? this.accentSilver,
    );
  }

  @override
  PyureThemeExtension lerp(
    covariant ThemeExtension<PyureThemeExtension>? other,
    double t,
  ) {
    if (other is! PyureThemeExtension) return this;
    return PyureThemeExtension(
      playerGlowColor:
          Color.lerp(playerGlowColor, other.playerGlowColor, t) ??
          playerGlowColor,
      miniPlayerSurface:
          Color.lerp(miniPlayerSurface, other.miniPlayerSurface, t) ??
          miniPlayerSurface,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t) ?? cardBorder,
      subtleText: Color.lerp(subtleText, other.subtleText, t) ?? subtleText,
      accentSilver:
          Color.lerp(accentSilver, other.accentSilver, t) ?? accentSilver,
    );
  }
}

/// Чёрно-серая минималистичная тема для Pyure.
abstract final class PyureTheme {
  static const Color _canvas = Color(0xFF0C0C0D);
  static const Color _surfaceLow = Color(0xFF131315);
  static const Color _surface = Color(0xFF18181B);
  static const Color _surfaceHigh = Color(0xFF212126);
  static const Color _surfaceHighest = Color(0xFF2B2B31);
  static const Color _primarySilver = Color(0xFFE4E4E7);
  static const Color _secondaryGrey = Color(0xFFA1A1AA);
  static const Color _textLight = Color(0xFFF4F4F5);
  static const Color _mutedGrey = Color(0xFF8E8E98);
  static const Color _outline = Color(0xFF2A2A30);

  static ThemeData dark() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: _primarySilver,
      onPrimary: Color(0xFF111113),
      primaryContainer: Color(0xFF2D2D33),
      onPrimaryContainer: _textLight,
      secondary: _secondaryGrey,
      onSecondary: Color(0xFF141417),
      secondaryContainer: Color(0xFF26262B),
      onSecondaryContainer: _primarySilver,
      tertiary: Color(0xFFD4D4D8),
      onTertiary: Color(0xFF141417),
      error: Color(0xFFEF6C6C),
      onError: Color(0xFF260909),
      surface: _canvas,
      onSurface: _textLight,
      surfaceContainerLowest: Color(0xFF09090A),
      surfaceContainerLow: _surfaceLow,
      surfaceContainer: _surface,
      surfaceContainerHigh: _surfaceHigh,
      surfaceContainerHighest: _surfaceHighest,
      onSurfaceVariant: _mutedGrey,
      outline: _outline,
      outlineVariant: Color(0xFF202025),
    );

    const extension = PyureThemeExtension(
      playerGlowColor: Color(0x22FFFFFF),
      miniPlayerSurface: Color(0xFF141417),
      cardBorder: _outline,
      subtleText: _mutedGrey,
      accentSilver: _secondaryGrey,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _canvas,
      extensions: const <ThemeExtension<dynamic>>[extension],
      appBarTheme: const AppBarTheme(
        backgroundColor: _canvas,
        foregroundColor: _textLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _outline),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: _outline,
        thickness: 1,
        space: 1,
      ),
      scrollbarTheme: ScrollbarThemeData(
        interactive: true,
        thickness: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return 10.0;
          }
          return 7.0;
        }),
        radius: const Radius.circular(8),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return _primarySilver.withValues(alpha: 0.75);
          }
          if (states.contains(WidgetState.hovered)) {
            return _primarySilver.withValues(alpha: 0.5);
          }
          return _mutedGrey.withValues(alpha: 0.38);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return _surfaceHigh.withValues(alpha: 0.5);
          }
          return Colors.transparent;
        }),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surfaceLow,
        indicatorColor: _primarySilver.withValues(alpha: 0.14),
        elevation: 0,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? _primarySilver : _mutedGrey,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            color: isSelected ? _primarySilver : _mutedGrey,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: _surfaceLow,
        indicatorColor: _primarySilver.withValues(alpha: 0.14),
        selectedIconTheme: const IconThemeData(color: _primarySilver, size: 22),
        unselectedIconTheme: const IconThemeData(color: _mutedGrey, size: 22),
        selectedLabelTextStyle: const TextStyle(
          color: _primarySilver,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: _mutedGrey,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        hintStyle: const TextStyle(color: _mutedGrey),
        prefixIconColor: _mutedGrey,
        suffixIconColor: _mutedGrey,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _primarySilver, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _surface,
        selectedColor: _primarySilver.withValues(alpha: 0.16),
        side: const BorderSide(color: _outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(color: _textLight, fontSize: 13),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _surfaceHigh,
        contentTextStyle: const TextStyle(color: _textLight),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _outline),
        ),
      ),
    );
  }
}

extension PyureThemeBuildContext on BuildContext {
  PyureThemeExtension get pyureTheme =>
      Theme.of(this).extension<PyureThemeExtension>()!;
}
