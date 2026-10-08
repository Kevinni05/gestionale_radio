import 'dart:async';
import 'package:flutter/material.dart';

/// Disposes pushed screens and their private state when the account changes.
class SessionRouteGuard extends StatefulWidget {
  const SessionRouteGuard({
    super.key,
    required this.identities,
    required this.initialIdentity,
    required this.child,
  });
  final Stream<String?> identities;
  final String? initialIdentity;
  final Widget child;

  @override
  State<SessionRouteGuard> createState() => _SessionRouteGuardState();
}

class _SessionRouteGuardState extends State<SessionRouteGuard> {
  late final StreamSubscription<String?> _subscription;
  String? _identity;

  @override
  void initState() {
    super.initState();
    _identity = widget.initialIdentity;
    _subscription = widget.identities.listen((identity) {
      if (identity == _identity) return;
      _identity = identity;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
