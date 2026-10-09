import 'package:flutter/material.dart';
import '../services/api_connection_status.dart';

class ApiConnectionBadge extends StatefulWidget {
  const ApiConnectionBadge({super.key, this.controller});
  final ApiConnectionController? controller;
  @override
  State<ApiConnectionBadge> createState() => _ApiConnectionBadgeState();
}

class _ApiConnectionBadgeState extends State<ApiConnectionBadge>
    with WidgetsBindingObserver {
  late final _controller = widget.controller ?? ApiConnectionController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.resume();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.resume();
    } else {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.pause();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final (label, color) = switch (_controller.status) {
        ApiConnectionStatus.online => ('ONLINE', const Color(0xFF45D995)),
        ApiConnectionStatus.offline => (
          'SERVIZIO OFFLINE',
          const Color(0xFFFFA366),
        ),
        ApiConnectionStatus.checking => ('IN VERIFICA', Colors.white70),
      };
      return Semantics(
        liveRegion: true,
        label: 'Connessione RadioTech: $label',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 7, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
