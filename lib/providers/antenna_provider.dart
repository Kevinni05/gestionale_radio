import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/antenna.dart';

final antennaCollectionProvider =
    Provider<CollectionReference<Map<String, dynamic>>>(
      (ref) => FirebaseFirestore.instance.collection('antennas'),
    );

final antennaDocumentProvider = FutureProvider.family<Antenna, String>((
  ref,
  antennaId,
) async {
  final collection = ref.watch(antennaCollectionProvider);
  final snapshot = await collection.doc(antennaId).get();
  if (!snapshot.exists) {
    throw StateError('Antenna non trovata: $antennaId');
  }
  return Antenna.fromFirestore(snapshot);
});
