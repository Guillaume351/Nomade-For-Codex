import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class AppMotion {
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);

  static const Curve standardCurve = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve emphasizedCurve = Cubic(0.2, 0.8, 0.2, 1.0);
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platform = getPlatform(context);
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    return const ClampingScrollPhysics();
  }

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

Route<T> buildAppPageRoute<T>(BuildContext context, Widget page) {
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return CupertinoPageRoute<T>(builder: (_) => page);
  }

  return PageRouteBuilder<T>(
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.medium,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.standardCurve,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.018),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.992, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = AppMotion.slow,
    this.delay = Duration.zero,
    this.beginOffset = const Offset(0, 0.03),
    this.curve = AppMotion.standardCurve,
  });

  final Widget child;
  final Duration duration;
  final Duration delay;
  final Offset beginOffset;
  final Curve curve;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  Timer? _delayTimer;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: widget.beginOffset,
    end: Offset.zero,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant FadeSlideIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration ||
        oldWidget.delay != widget.delay ||
        oldWidget.beginOffset != widget.beginOffset ||
        oldWidget.curve != widget.curve) {
      _controller.duration = widget.duration;
      _controller.reset();
      _delayTimer?.cancel();
      _start();
    }
  }

  void _start() {
    if (widget.delay > Duration.zero) {
      _delayTimer = Timer(widget.delay, () {
        if (!mounted) {
          return;
        }
        _controller.forward();
      });
      return;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    required this.color,
    this.size = 8,
  });

  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 2.7,
      height: widget.size * 2.7,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          final ringScale = 1 + (0.7 * (1 - t));
          final ringOpacity = (1 - t).clamp(0, 1) * 0.4;
          final coreScale = 0.92 + (0.08 * t);

          return Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: ringOpacity * 0.45,
                child: Transform.scale(
                  scale: ringScale,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: coreScale,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AppAmbientBackground extends StatelessWidget {
  const AppAmbientBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.12,
                    ),
                    theme.scaffoldBackgroundColor,
                    scheme.tertiary.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.17 : 0.08,
                    ),
                  ],
                ),
              ),
            ),
            IgnorePointer(
              child: Stack(
                children: [
                  Positioned(
                    top: -height * 0.16,
                    right: -width * 0.22,
                    child: _AmbientOrb(
                      size: width * 0.68,
                      color: scheme.primary.withValues(
                        alpha: theme.brightness == Brightness.dark ? 0.2 : 0.14,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -height * 0.24,
                    left: -width * 0.28,
                    child: _AmbientOrb(
                      size: width * 0.78,
                      color: scheme.secondary.withValues(
                        alpha:
                            theme.brightness == Brightness.dark ? 0.16 : 0.11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            child,
          ],
        );
      },
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0.16),
            Colors.transparent,
          ],
          stops: const [0.1, 0.55, 1],
        ),
      ),
    );
  }
}
