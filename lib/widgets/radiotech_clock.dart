import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/radiotech_theme.dart';

abstract final class ItalianDate {
  static const months = [
    'Gennaio',
    'Febbraio',
    'Marzo',
    'Aprile',
    'Maggio',
    'Giugno',
    'Luglio',
    'Agosto',
    'Settembre',
    'Ottobre',
    'Novembre',
    'Dicembre',
  ];
  static String day(DateTime value) =>
      '${value.day} ${months[value.month - 1]} ${value.year}';
  static String time(DateTime value) => [
    value.hour,
    value.minute,
    value.second,
  ].map((v) => v.toString().padLeft(2, '0')).join(':');
}

/// Only this small widget rebuilds each second; no API or dashboard reload.
class RadioTechClock extends StatefulWidget {
  const RadioTechClock({super.key, this.now});
  final DateTime Function()? now;
  @override
  State<RadioTechClock> createState() => _RadioTechClockState();
}

class _RadioTechClockState extends State<RadioTechClock>
    with WidgetsBindingObserver {
  Timer? _timer;
  late DateTime _now;
  bool _resumed = true;
  DateTime _read() => (widget.now?.call() ?? DateTime.now()).toLocal();
  @override
  void initState() {
    super.initState();
    _now = _read();
    WidgetsBinding.instance.addObserver(this);
  }

  void _sync() {
    _timer?.cancel();
    if (!_resumed || !TickerMode.valuesOf(context).enabled) return;
    _now = _read();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = _read());
    });
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
      setState(_sync);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    '${ItalianDate.day(_now)} - ${ItalianDate.time(_now)}',
    key: const ValueKey('home-live-clock'),
    style: const TextStyle(
      color: RadioTechTheme.muted,
      fontSize: 12,
      height: 1.5,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );
}
