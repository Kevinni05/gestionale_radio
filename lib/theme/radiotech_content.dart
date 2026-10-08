import 'package:flutter/material.dart';

/// Keeps scrollable content centred and gives every screen the same reading width.
class RadioTechContent extends StatelessWidget {
  const RadioTechContent({super.key, required this.child, this.maxWidth = 960});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}
