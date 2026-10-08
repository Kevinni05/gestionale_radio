import 'package:cloud_firestore/cloud_firestore.dart';

class Antenna {
  final String id;
  final String name;
  final String assetType;
  final String? parentAssetId;
  final String? serialNumber;
  final String? manufacturer;
  final String? model;
  final String? installationDate;
  final double latitude;
  final double longitude;
  final Map<String, dynamic> specs;
  final List<String> checklistTemplate;

  const Antenna({
    required this.id,
    required this.name,
    this.assetType = 'ANTENNA',
    this.parentAssetId,
    this.serialNumber,
    this.manufacturer,
    this.model,
    this.installationDate,
    required this.latitude,
    required this.longitude,
    required this.specs,
    required this.checklistTemplate,
  });

  factory Antenna.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    return Antenna(
      id: doc.id,
      name: data['name'] as String? ?? 'Antenna sconosciuta',
      assetType: data['assetType'] as String? ?? 'ANTENNA',
      parentAssetId: data['parentAssetId'] as String?,
      serialNumber: data['serialNumber'] as String?,
      manufacturer: data['manufacturer'] as String?,
      model: data['model'] as String?,
      installationDate: data['installationDate'] as String?,
      latitude: (data['lat'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['lng'] as num?)?.toDouble() ?? 0.0,
      specs: Map<String, dynamic>.from(
        data['specs'] as Map<String, dynamic>? ?? {},
      ),
      checklistTemplate: List<String>.from(
        data['checklist_template'] as List<dynamic>? ?? [],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'assetType': assetType,
      if (parentAssetId != null) 'parentAssetId': parentAssetId,
      if (serialNumber != null) 'serialNumber': serialNumber,
      if (manufacturer != null) 'manufacturer': manufacturer,
      if (model != null) 'model': model,
      if (installationDate != null) 'installationDate': installationDate,
      'lat': latitude,
      'lng': longitude,
      'specs': specs,
      'checklist_template': checklistTemplate,
    };
  }
}
