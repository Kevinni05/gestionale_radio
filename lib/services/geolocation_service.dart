import 'dart:math';

import 'package:geolocator/geolocator.dart';

enum LocationPermissionStatus {
  granted,
  denied,
  deniedForever,
  servicesDisabled,
  unknown,
}

class AntennaLocation {
  final double latitude;
  final double longitude;

  const AntennaLocation({required this.latitude, required this.longitude});
}

class LocationValidationResult {
  final bool isValid;
  final double? distanceMeters;
  final LocationPermissionStatus permissionStatus;
  final String message;

  const LocationValidationResult({
    required this.isValid,
    required this.permissionStatus,
    required this.message,
    this.distanceMeters,
  });
}

class GeolocationService {
  const GeolocationService();

  Future<LocationPermissionStatus> _checkPermissionStatus() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionStatus.servicesDisabled;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      return LocationPermissionStatus.granted;
    }

    if (permission == LocationPermission.denied) {
      return LocationPermissionStatus.denied;
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionStatus.deniedForever;
    }

    return LocationPermissionStatus.unknown;
  }

  Future<LocationPermissionStatus> requestLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionStatus.servicesDisabled;
    }

    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      return LocationPermissionStatus.granted;
    }

    if (permission == LocationPermission.denied) {
      return LocationPermissionStatus.denied;
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionStatus.deniedForever;
    }

    return LocationPermissionStatus.unknown;
  }

  Future<Position> getCurrentPosition() async {
    final permissionStatus = await _checkPermissionStatus();
    if (permissionStatus != LocationPermissionStatus.granted) {
      throw LocationServiceException(
        'Permesso di posizione non concesso o servizi non disponibili.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  Future<LocationValidationResult> validateAntennaProximity(
    AntennaLocation antennaLocation, {
    double maxDistanceMeters = 50,
  }) async {
    final permissionStatus = await _checkPermissionStatus();
    if (permissionStatus != LocationPermissionStatus.granted) {
      return LocationValidationResult(
        isValid: false,
        permissionStatus: permissionStatus,
        message: permissionStatus == LocationPermissionStatus.servicesDisabled
            ? 'Servizi di localizzazione disabilitati. Attivali per procedere.'
            : permissionStatus == LocationPermissionStatus.deniedForever
            ? 'Permessi di posizione negati in modo permanente. Apri impostazioni per consentirli.'
            : 'Permessi di posizione non concessi. Consenti l’accesso alla posizione.',
      );
    }

    final currentPosition = await getCurrentPosition();
    final distance = haversineDistanceInMeters(
      antennaLocation.latitude,
      antennaLocation.longitude,
      currentPosition.latitude,
      currentPosition.longitude,
    );

    final isValid = distance <= maxDistanceMeters;
    return LocationValidationResult(
      isValid: isValid,
      distanceMeters: distance,
      permissionStatus: permissionStatus,
      message: isValid
          ? 'Posizione valida: sei entro ${distance.toStringAsFixed(1)} m dall’antenna.'
          : 'Posizione fuori range: sei a ${distance.toStringAsFixed(1)} m dall’antenna. Avvicinati entro $maxDistanceMeters m.',
    );
  }

  double haversineDistanceInMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0; // metri
    final latDelta = _degreesToRadians(lat2 - lat1);
    final lngDelta = _degreesToRadians(lng2 - lng1);

    final a =
        (sin(latDelta / 2) * sin(latDelta / 2)) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            (sin(lngDelta / 2) * sin(lngDelta / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) => degrees * (pi / 180.0);
}

class LocationServiceException implements Exception {
  final String message;
  const LocationServiceException(this.message);

  @override
  String toString() => 'LocationServiceException: $message';
}
