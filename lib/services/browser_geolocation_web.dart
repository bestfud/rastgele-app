// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'package:flutter/foundation.dart';

import 'browser_coordinates.dart';

Future<BrowserCoordinates?> getBrowserCoordinatesImpl() async {
  try {
    final position = await html.window.navigator.geolocation.getCurrentPosition(
      enableHighAccuracy: true,
      timeout: const Duration(seconds: 8),
      maximumAge: const Duration(minutes: 10),
    );
    final coords = position.coords;
    final latitude = coords?.latitude;
    final longitude = coords?.longitude;
    if (latitude == null || longitude == null) {
      debugPrint('[MAP_LOC] getCurrentPosition failure error=coords_null');
      return null;
    }

    return BrowserCoordinates(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
  } catch (error) {
    debugPrint('[MAP_LOC] getCurrentPosition failure error=$error');
    return null;
  }
}
