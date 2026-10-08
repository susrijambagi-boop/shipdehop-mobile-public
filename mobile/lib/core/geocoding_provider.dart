import '../models/confirmed_location.dart';

abstract class GeocodingProvider {
  Future<List<ConfirmedLocation>> search(String query);
  Future<ConfirmedLocation> reverseGeocode(double latitude, double longitude);
}

class DevelopmentGeocodingAdapter implements GeocodingProvider {
  const DevelopmentGeocodingAdapter();

  static const List<ConfirmedLocation> _testPlaces = [
    ConfirmedLocation(
      displayLabel: 'Mumbai, Maharashtra',
      formattedAddress: 'Mumbai, Maharashtra, India',
      latitude: 19.0760,
      longitude: 72.8777,
      countryCode: 'IN',
      countryName: 'India',
      administrativeArea: 'Maharashtra',
      locality: 'Mumbai',
      postalCode: '400001',
      provider: 'development_adapter',
    ),
    ConfirmedLocation(
      displayLabel: 'Pune, Maharashtra',
      formattedAddress: 'Pune, Maharashtra, India',
      latitude: 18.5204,
      longitude: 73.8567,
      countryCode: 'IN',
      countryName: 'India',
      administrativeArea: 'Maharashtra',
      locality: 'Pune',
      postalCode: '411001',
      provider: 'development_adapter',
    ),
    ConfirmedLocation(
      displayLabel: 'Bangalore, Karnataka',
      formattedAddress: 'Bangalore, Karnataka, India',
      latitude: 12.9716,
      longitude: 77.5946,
      countryCode: 'IN',
      countryName: 'India',
      administrativeArea: 'Karnataka',
      locality: 'Bangalore',
      postalCode: '560001',
      provider: 'development_adapter',
    ),
    ConfirmedLocation(
      displayLabel: 'Goa, India',
      formattedAddress: 'Panaji, Goa, India',
      latitude: 15.2993,
      longitude: 74.1240,
      countryCode: 'IN',
      countryName: 'India',
      administrativeArea: 'Goa',
      locality: 'Panaji',
      postalCode: '403001',
      provider: 'development_adapter',
    ),
    ConfirmedLocation(
      displayLabel: 'Port Blair, Andaman & Nicobar',
      formattedAddress: 'Port Blair, Andaman and Nicobar Islands, India',
      latitude: 11.6234,
      longitude: 92.7265,
      countryCode: 'IN',
      countryName: 'India',
      administrativeArea: 'Andaman and Nicobar Islands',
      locality: 'Port Blair',
      postalCode: '744101',
      provider: 'development_adapter',
    ),
    ConfirmedLocation(
      displayLabel: 'Kavaratti, Lakshadweep',
      formattedAddress: 'Kavaratti, Lakshadweep, India',
      latitude: 10.5669,
      longitude: 72.6420,
      countryCode: 'IN',
      countryName: 'India',
      administrativeArea: 'Lakshadweep',
      locality: 'Kavaratti',
      postalCode: '682555',
      provider: 'development_adapter',
    ),
  ];

  @override
  Future<List<ConfirmedLocation>> search(String query) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return _testPlaces;

    final results = _testPlaces.where((place) {
      final label = place.displayLabel.toLowerCase();
      final addr = place.formattedAddress.toLowerCase();
      final locality = place.locality?.toLowerCase() ?? '';
      final state = place.administrativeArea?.toLowerCase() ?? '';
      return label.contains(clean) ||
          addr.contains(clean) ||
          locality.contains(clean) ||
          state.contains(clean);
    }).toList();

    return results;
  }

  @override
  Future<ConfirmedLocation> reverseGeocode(double latitude, double longitude) async {
    // 1. Check if matches or is close to a predefined test place
    for (final place in _testPlaces) {
      final latDiff = (place.latitude - latitude).abs();
      final lngDiff = (place.longitude - longitude).abs();
      if (latDiff < 0.08 && lngDiff < 0.08) {
        return ConfirmedLocation(
          displayLabel: place.displayLabel,
          formattedAddress: place.formattedAddress,
          latitude: latitude,
          longitude: longitude,
          countryCode: place.countryCode,
          countryName: place.countryName,
          administrativeArea: place.administrativeArea,
          locality: place.locality,
          postalCode: place.postalCode,
          provider: 'development_adapter',
        );
      }
    }

    // 2. Boundary check heuristics for India
    final isLakshadweep = latitude >= 8.0 && latitude <= 12.6 && longitude >= 71.3 && longitude <= 74.2;
    final isAndaman = latitude >= 6.7 && latitude <= 14.1 && longitude >= 92.1 && longitude <= 94.3;
    final isMainlandIndia = latitude >= 8.0 && latitude <= 35.5 && longitude >= 68.1 && longitude <= 97.4 &&
        !(latitude >= 24.0 && latitude <= 37.0 && longitude < 72.5) && // Exclude Pakistan
        !(latitude >= 26.3 && latitude <= 30.5 && longitude >= 80.0 && longitude <= 88.2) && // Exclude Nepal
        !(latitude >= 20.6 && latitude <= 26.7 && longitude >= 88.0 && longitude <= 92.7) && // Exclude Bangladesh
        !(latitude >= 5.8 && latitude <= 9.9 && longitude >= 79.6 && longitude <= 82.0); // Exclude Sri Lanka

    if (isLakshadweep || isAndaman || isMainlandIndia) {
      return ConfirmedLocation(
        displayLabel: 'Pinned Location (${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)})',
        formattedAddress: 'Confirmed Location Point, India',
        latitude: latitude,
        longitude: longitude,
        countryCode: 'IN',
        countryName: 'India',
        locality: 'India',
        provider: 'development_adapter',
      );
    }

    // 3. Foreign / Unsupported Location (Preserve actual foreign country metadata, NEVER fake IN)
    return ConfirmedLocation(
      displayLabel: 'Location (${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)})',
      formattedAddress: 'Location Outside India (${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)})',
      latitude: latitude,
      longitude: longitude,
      countryCode: 'UNSUPPORTED',
      countryName: 'Outside India',
      provider: 'development_adapter',
    );
  }
}

class GeocodingException implements Exception {
  const GeocodingException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BackendGeocodingAdapter implements GeocodingProvider {
  final dynamic apiClient;
  final GeocodingProvider? fallbackAdapter;
  const BackendGeocodingAdapter({this.apiClient, this.fallbackAdapter});

  @override
  Future<List<ConfirmedLocation>> search(String query) async {
    final client = apiClient;
    if (client == null) {
      if (fallbackAdapter != null) {
        return fallbackAdapter!.search(query);
      }
      throw const GeocodingException('Geocoding requires an authenticated ApiClient or explicit test adapter.');
    }

    try {
      final res = await client.get('/location/search?q=${Uri.encodeComponent(query)}', requireAuth: false);
      final list = (res['results'] as List<dynamic>?) ?? [];
      return list.map((json) {
        final m = json as Map<String, dynamic>;
        return ConfirmedLocation(
          displayLabel: m['displayLabel']?.toString() ?? query,
          formattedAddress: m['formattedAddress']?.toString() ?? '$query, India',
          latitude: (m['latitude'] as num).toDouble(),
          longitude: (m['longitude'] as num).toDouble(),
          countryCode: m['countryCode']?.toString() ?? 'IN',
          countryName: m['countryName']?.toString() ?? 'India',
          administrativeArea: m['state']?.toString(),
          locality: m['locality']?.toString(),
          postalCode: m['postalCode']?.toString(),
          provider: m['provenance']?.toString() ?? 'backend-production-geocoder',
        );
      }).toList();
    } catch (e) {
      if (e is GeocodingException) rethrow;
      throw GeocodingException('Location search failed: $e');
    }
  }

  @override
  Future<ConfirmedLocation> reverseGeocode(double latitude, double longitude) async {
    final client = apiClient;
    if (client == null) {
      if (fallbackAdapter != null) {
        return fallbackAdapter!.reverseGeocode(latitude, longitude);
      }
      throw const GeocodingException('Geocoding requires an authenticated ApiClient or explicit test adapter.');
    }

    try {
      final res = await client.get('/location/reverse?lat=$latitude&lon=$longitude', requireAuth: false);
      if (res == null || res is! Map<String, dynamic>) {
        throw const GeocodingException('Location reverse lookup returned empty result');
      }
      return ConfirmedLocation(
        displayLabel: res['displayLabel']?.toString() ?? 'Verified Location',
        formattedAddress: res['formattedAddress']?.toString() ?? 'India',
        latitude: (res['latitude'] as num).toDouble(),
        longitude: (res['longitude'] as num).toDouble(),
        countryCode: res['countryCode']?.toString() ?? 'IN',
        countryName: res['countryName']?.toString() ?? 'India',
        administrativeArea: res['state']?.toString(),
        locality: res['locality']?.toString(),
        postalCode: res['postalCode']?.toString(),
        provider: res['provenance']?.toString() ?? 'backend-production-geocoder',
      );
    } catch (e) {
      if (e is GeocodingException) rethrow;
      throw GeocodingException('Reverse geocoding failed: $e');
    }
  }
}
