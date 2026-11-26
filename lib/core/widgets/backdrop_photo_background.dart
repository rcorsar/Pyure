import 'package:material_ui/material_ui.dart';

/// Фоновая фотография с мягким тёмным градиентным затемнением для экранов
/// альбома и полноэкранного плеера.
class BackdropPhotoBackground extends StatelessWidget {
  const BackdropPhotoBackground({
    this.topScrimAlpha = 0.55,
    this.middleScrimAlpha = 0.78,
    this.bottomScrimAlpha = 0.90,
    super.key,
  });

  final double topScrimAlpha;
  final double middleScrimAlpha;
  final double bottomScrimAlpha;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: Image.asset(
            'assets/images/album_bg.jpg',
            fit: BoxFit.cover,
            cacheWidth: 1280,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0C0C0D).withValues(alpha: topScrimAlpha),
                const Color(0xFF0C0C0D).withValues(alpha: middleScrimAlpha),
                const Color(0xFF0C0C0D).withValues(alpha: bottomScrimAlpha),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
