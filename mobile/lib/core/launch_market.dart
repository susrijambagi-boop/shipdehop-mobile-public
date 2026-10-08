import '../models/confirmed_location.dart';

/// Single source of truth for the first ShipdeHop launch market.
///
/// The initial production release is intentionally India-only. Keep this guard
/// at shared domain boundaries so UI, location services and transactional
/// flows cannot accidentally enable another country just because a map or GPS
/// provider can return it.
class LaunchMarket {
  const LaunchMarket._();

  static const String countryCode = 'IN';
  static const String countryName = 'India';
  static const String currency = 'INR';
  static const String jurisdictionCode = 'IN';

  static const String unsupportedMessage =
      'ShipdeHop is currently available only in India. Search for an Indian city, area or address instead.';

  // Broad launch bounds that include mainland India, Lakshadweep and the
  // Andaman & Nicobar Islands. Country-code validation remains the primary
  // check when the geocoder can provide it.
  static bool containsCoordinates(double latitude, double longitude) {
    return latitude >= 6.0 &&
        latitude <= 38.0 &&
        longitude >= 68.0 &&
        longitude <= 98.5;
  }

  static bool isIndiaCode(String? code) {
    final value = code?.trim().toUpperCase() ?? '';
    return value == 'IN' || value == 'IND' || value == 'INDIA';
  }

  static bool isSupportedLocation(ConfirmedLocation location) {
    return isIndiaCode(location.countryCode) &&
        containsCoordinates(location.latitude, location.longitude);
  }

  static bool isSupportedRoute(
    ConfirmedLocation origin,
    ConfirmedLocation destination,
  ) {
    return isSupportedLocation(origin) && isSupportedLocation(destination);
  }
}