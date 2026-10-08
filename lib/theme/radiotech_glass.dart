import 'dart:ui';
import 'package:flutter/material.dart';
import 'radiotech_theme.dart';

class RadioTechGlass extends StatelessWidget {
  const RadioTechGlass({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 16,
    this.highlight = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool highlight;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xB8232332), Color(0xC912131D)],
          ),
          border: Border.all(
            color: highlight ? RadioTechTheme.coral : RadioTechTheme.border,
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}
