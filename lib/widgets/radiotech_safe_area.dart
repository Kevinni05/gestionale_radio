import 'package:flutter/material.dart';

/// Keeps the navigator, dialogs and bottom controls above Android system buttons.
class RadioTechSafeArea extends StatelessWidget {
  const RadioTechSafeArea({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    left: false,
    right: false,
    maintainBottomViewPadding: true,
    child: child,
  );
}
