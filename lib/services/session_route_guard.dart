import 'dart:async';
import 'package:flutter/material.dart';
import 'app_navigation.dart';

/// Disposes pushed screens and their private state when the account changes.
class SessionRouteGuard extends StatefulWidget {
  const SessionRouteGuard({
    super.key,
    required this.identities,
    required this.initialIdentity,
    required this.child,
    this.scopes,
    this.onScopeChanged,
  });
  final Stream<String?> identities;
  final String? initialIdentity;
  final Widget child;
  final Stream<String?>? scopes;
  final VoidCallback? onScopeChanged;

  @override
  State<SessionRouteGuard> createState() => _SessionRouteGuardState();
}

class _SessionRouteGuardState extends State<SessionRouteGuard> {
  late final StreamSubscription<String?> _subscription;
  String? _identity;
  String? _scope;
  int _scopeRevision = 0;
  StreamSubscription<String?>? _scopeSubscription;

  @override
  void initState() {
    super.initState();
    _identity = widget.initialIdentity;
    _subscription = widget.identities.listen((identity) {
      if (identity == _identity) return;
      _identity = identity;
      _scope = null;
      setState(() => _scopeRevision++);
      AppNavigation.clearRequests();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
    _scopeSubscription = widget.scopes?.listen(
      (scope) {
        final previous = _scope;
        _scope = scope;
        if (previous == null || scope == previous) return;
        widget.onScopeChanged?.call();
        setState(() => _scopeRevision++);
        AppNavigation.clearRequests();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      },
      onError: (Object _) {
        /* Online access verification handles connectivity failures. */
      },
    );
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_scopeSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: ValueKey(_scopeRevision), child: widget.child);
}
