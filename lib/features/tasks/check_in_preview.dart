import 'package:flutter/material.dart';

/// Coordinates are submitted only after the technician confirms this preview.
Future<bool> confirmCheckIn(
  BuildContext context, {
  required String antenna,
  required double accuracy,
  double? distance,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verifica il check-in'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(antenna),
              const SizedBox(height: 12),
              Text(
                distance == null
                    ? 'Distanza non disponibile: coordinate impianto assenti.'
                    : 'Distanza dall’impianto: ${distance.round()} m',
              ),
              Text('Accuratezza GPS: circa ${accuracy.round()} m'),
              if (accuracy > 100)
                const Text(
                  'Il segnale è impreciso. Spostati all’aperto e riprova prima di inviare.',
                ),
              const SizedBox(height: 12),
              const Text(
                'Il server verifica la posizione e conferma il check-in. Se sei fuori area, contatta il responsabile per una deroga tracciata.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla e riprova'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Invia posizione'),
          ),
        ],
      ),
    ) ??
    false;
