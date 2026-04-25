import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'browser_coordinates.dart';

Future<BrowserCoordinates?> getBrowserCoordinatesImpl() async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[MAP_LOC] getCurrentPosition failure error=service_disabled');
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint(
          '[MAP_LOC] getCurrentPosition failure error=permission_denied');
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    return BrowserCoordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  } catch (error) {
    debugPrint('[MAP_LOC] getCurrentPosition failure error=$error');
    return null;
  }
}
