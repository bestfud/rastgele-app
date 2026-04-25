import 'browser_geolocation_io.dart'
    if (dart.library.html) 'browser_geolocation_web.dart';
import 'browser_coordinates.dart';

export 'browser_coordinates.dart';

Future<BrowserCoordinates?> getBrowserCoordinates() {
  return getBrowserCoordinatesImpl();
}
