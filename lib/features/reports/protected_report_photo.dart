import 'dart:typed_data';
import 'package:flutter/material.dart';

/// The reader authenticates/decrypts the stored photo; plaintext stays in memory.
class ProtectedReportPhoto extends StatelessWidget {
  const ProtectedReportPhoto({
    super.key,
    required this.bytes,
    this.semanticLabel = 'Foto allegata',
  });
  final Future<Uint8List> bytes;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 110,
    height: 110,
    child: FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snapshot) {
        Widget unreadable() => const Center(child: Text('Foto non leggibile'));
        if (snapshot.hasError) return unreadable();
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Image.memory(
          snapshot.data!,
          semanticLabel: semanticLabel,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => unreadable(),
        );
      },
    ),
  );
}
