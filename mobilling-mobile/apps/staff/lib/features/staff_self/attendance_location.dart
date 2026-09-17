import 'dart:async' show TimeoutException;

import 'package:geolocator/geolocator.dart';

/// Thrown for every way [currentPosition] can fail — a location services
/// toggle, a denied permission, or a timeout — each with a message the
/// check-in screen can show directly.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One GPS read for a check-in/out tap — never continuous, never
/// background; see the doc comment on `DeviceBinding` for why this app
/// asks for "when in use" only.
Future<Position> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationUnavailable(
      'Turn on location services to check in.',
    );
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied) {
    throw const LocationUnavailable(
      'Location permission is required to check in.',
    );
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationUnavailable(
      'Location permission was denied. Enable it for MoBilling in your '
      'phone settings to check in.',
    );
  }

  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  } on TimeoutException {
    throw const LocationUnavailable(
      'Could not get your location in time. Try again outdoors or near a '
      'window.',
    );
  }
}
