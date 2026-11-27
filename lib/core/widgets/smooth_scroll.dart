import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// Контроллер прокрутки с плавной интерполяцией шагов колёсика мыши
/// без потери мгновенного отклика при перетаскивании полосы прокрутки.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({super.initialScrollOffset, super.keepScrollOffset});

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  double? _wheelTarget;
  int _animToken = 0;

  @override
  void jumpTo(double value) {
    _animToken++;
    _wheelTarget = null;
    super.jumpTo(value);
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    _animToken++;
    _wheelTarget = null;
    return super.drag(details, dragCancelCallback);
  }

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      _animToken++;
      _wheelTarget = null;
      super.pointerScroll(delta);
      return;
    }

    final base = _wheelTarget ?? pixels;
    final target = (base + delta * 1.1).clamp(
      minScrollExtent,
      maxScrollExtent,
    );
    if ((target - pixels).abs() < 0.1) return;

    _wheelTarget = target;
    final token = ++_animToken;
    unawaited(
      animateTo(
        target,
        duration: const Duration(milliseconds: 165),
        curve: Curves.easeOutCubic,
      ).whenComplete(() {
        if (token == _animToken) {
          _wheelTarget = null;
        }
      }),
    );
  }
}

/// Оборачивает прокручиваемый контент в [SmoothScrollController] и интерактивный
/// [Scrollbar] для плавного скролла колёсиком и боковым ползунком.
class SmoothScrollArea extends StatefulWidget {
  const SmoothScrollArea({
    required this.builder,
    this.thumbVisibility = false,
    super.key,
  });

  final Widget Function(BuildContext context, ScrollController controller)
  builder;
  final bool thumbVisibility;

  @override
  State<SmoothScrollArea> createState() => _SmoothScrollAreaState();
}

class _SmoothScrollAreaState extends State<SmoothScrollArea> {
  late final SmoothScrollController _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: widget.thumbVisibility,
      interactive: true,
      child: widget.builder(context, _controller),
    );
  }
}
