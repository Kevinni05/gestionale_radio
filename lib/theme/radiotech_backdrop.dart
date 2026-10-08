import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared background paints behind routes and never intercepts input.
class RadioTechBackdrop extends StatefulWidget {
  const RadioTechBackdrop({super.key, required this.child});
  final Widget child;
  @override
  State<RadioTechBackdrop> createState() => _RadioTechBackdropState();
}

class _RadioTechBackdropState extends State<RadioTechBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  );
  bool _resumed = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _sync() {
    if (_resumed &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled) {
      if (!_motion.isAnimating) {
        _motion.repeat(reverse: true);
      }
    } else {
      _motion.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (mounted) {
      _sync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      IgnorePointer(
        child: ExcludeSemantics(
          child: RepaintBoundary(
            child: CustomPaint(painter: _AuroraPainter(_motion)),
          ),
        ),
      ),
      widget.child,
    ],
  );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.motion) : super(repaint: motion);
  final Animation<double> motion;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = const Color(0xFF08090D));
    final shift = math.sin(motion.value * math.pi) * .14;
    for (final glow in [
      (
        Offset(size.width * (.12 + shift), size.height * .2),
        const Color(0x448447BB),
      ),
      (
        Offset(size.width * (.9 - shift), size.height * .72),
        const Color(0x33FF6363),
      ),
      (
        Offset(size.width * .8, size.height * (.1 + shift)),
        const Color(0x284D77CC),
      ),
    ]) {
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = RadialGradient(colors: [glow.$2, Colors.transparent])
              .createShader(
                Rect.fromCircle(
                  center: glow.$1,
                  radius: size.longestSide * .65,
                ),
              ),
      );
    }
    final grid = Paint()
      ..color = const Color(0x08FFFFFF)
      ..strokeWidth = .5;
    for (double x = 0; x < size.width; x += 64) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 64) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // Original signal geometry echoes the web illustration, behind content.
    canvas.save();
    canvas.translate(size.width * .8, size.height * (.14 + shift * .2));
    canvas.rotate(-.35 + shift * .2);
    final planeWidth = size.width * .56;
    for (var layer = 0; layer < 3; layer++) {
      final top = layer * 22.0;
      final plane = Path()
        ..moveTo(-planeWidth / 2, top)
        ..lineTo(0, top - planeWidth * .22)
        ..lineTo(planeWidth / 2, top)
        ..lineTo(0, top + planeWidth * .22)
        ..close();
      canvas.drawPath(
        plane,
        Paint()..color = Color.fromRGBO(255, 99, 99, .035 + layer * .012),
      );
      canvas.drawPath(
        plane,
        Paint()
          ..color = const Color(0x22FF6363)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) =>
      oldDelegate.motion != motion;
}

class RadioTechPageTransitions extends PageTransitionsBuilder {
  const RadioTechPageTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    final curve = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: curve.drive(
          Tween(begin: const Offset(.035, 0), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}
