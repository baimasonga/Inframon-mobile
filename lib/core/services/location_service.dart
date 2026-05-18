import 'dart:async';
import 'package:geolocator/geolocator.dart';

/// Result returned by [LocationService.getLocationWithFeedback].
/// Either [position] is non-null (success) or [errorMessage] explains why not.
class LocationResult {
  final Position? position;
  final String? errorMessage;
  const LocationResult({this.position, this.errorMessage});
  bool get hasLocation => position != null;
}

class LocationService {
  /// Simple getter — returns [Position] or null.
  /// Existing callers don't need changes.
  static Future<Position?> getCurrentLocation() async {
    final result = await getLocationWithFeedback();
    return result.position;
  }

  /// Full getter — returns a [LocationResult] with the position OR a specific
  /// human-readable error message explaining exactly why GPS failed.
  static Future<LocationResult> getLocationWithFeedback() async {
    // 1. Is the device GPS radio even on?
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocationResult(
        errorMessage:
            'Location services are off. Enable GPS in your device settings and try again.',
      );
    }

    // 2. Do we have (or can we get) permission?
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return const LocationResult(
          errorMessage:
              'Location permission denied. Allow InfraMon to access location when prompted.',
        );
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationResult(
        errorMessage:
            'Location permanently denied. Go to Settings > Apps > InfraMon > Permissions > Location.',
      );
    }

    // 3. Fetch a fresh, high-accuracy fix with a 12-second timeout
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationResult(position: pos);
    } on TimeoutException {
      return const LocationResult(
        errorMessage:
            'GPS timed out. Move to an open area or near a window and try again.',
      );
    } catch (_) {
      return const LocationResult(
        errorMessage: 'GPS unavailable. Please try again in a moment.',
      );
    }
  }
}
