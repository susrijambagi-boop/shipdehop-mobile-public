import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/confirmed_location.dart';
import '../models/route_result.dart';

class RoutingException implements Exception {
  const RoutingException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class RoutingProvider {
  Future<RouteResult> calculateRoute(ConfirmedLocation origin, ConfirmedLocation destination);
}

/// Actual OSRM Road Routing Adapter for Local Development
class OsrmRoutingAdapter implements RoutingProvider {
  const OsrmRoutingAdapter({http.Client? httpClient}) : _http = httpClient;

  final http.Client? _http;

  @override
  Future<RouteResult> calculateRoute(ConfirmedLocation origin, ConfirmedLocation destination) async {
    final client = _http ?? http.Client();
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await client.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = decoded['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes.first as Map<String, dynamic>;
          final distMeters = (route['distance'] as num).toDouble();
          final durationSecs = (route['duration'] as num).toDouble();
          final geometry = route['geometry'] as Map<String, dynamic>?;

          final polylinePoints = <ConfirmedLocation>[];
          if (geometry != null && geometry['coordinates'] is List) {
            final coords = geometry['coordinates'] as List;
            for (int i = 0; i < coords.length; i++) {
              final pt = coords[i] as List;
              final lng = (pt[0] as num).toDouble();
              final lat = (pt[1] as num).toDouble();
              polylinePoints.add(
                ConfirmedLocation(
                  displayLabel: i == 0
                      ? origin.displayLabel
                      : i == coords.length - 1
                          ? destination.displayLabel
                          : 'Waypoint $i',
                  formattedAddress: 'Road Waypoint',
                  latitude: lat,
                  longitude: lng,
                  countryCode: i == 0
                      ? origin.countryCode
                      : i == coords.length - 1
                          ? destination.countryCode
                          : '',
                  countryName: i == 0
                      ? origin.countryName
                      : i == coords.length - 1
                          ? destination.countryName
                          : '',
                  provider: 'development_osrm_demo',
                ),
              );
            }
          }

          if (polylinePoints.isEmpty) {
            polylinePoints.addAll([origin, destination]);
          }

          return RouteResult(
            origin: origin,
            destination: destination,
            polylinePoints: polylinePoints,
            distanceMeters: distMeters,
            durationSeconds: durationSecs,
            provider: 'development_osrm_demo',
          );
        }
        throw const RoutingException('Routing provider returned no valid route.');
      }
      throw RoutingException('Routing provider error (HTTP ${response.statusCode}).');
    } catch (e) {
      if (e is RoutingException) rethrow;
      throw RoutingException('Routing provider request failed: $e');
    }
  }
}

/// Explicit Fallback Approximation Adapter when routing service fails or is offline
class DevelopmentApproximationAdapter implements RoutingProvider {
  const DevelopmentApproximationAdapter();

  @override
  Future<RouteResult> calculateRoute(ConfirmedLocation origin, ConfirmedLocation destination) async {
    final distMeters = _calculateHaversineDistance(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );

    final durationSecs = (distMeters / 1000.0 / 55.0) * 3600.0;
    final points = _generatePolylinePoints(origin, destination, 6);

    return RouteResult(
      origin: origin,
      destination: destination,
      polylinePoints: points,
      distanceMeters: distMeters > 0 ? distMeters : 148000.0,
      durationSeconds: durationSecs > 0 ? durationSecs : 9900.0,
      provider: 'development_approximation',
    );
  }

  double _calculateHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _toRadians(double degree) => degree * pi / 180.0;

  List<ConfirmedLocation> _generatePolylinePoints(
    ConfirmedLocation origin,
    ConfirmedLocation destination,
    int steps,
  ) {
    final list = <ConfirmedLocation>[
      ConfirmedLocation(
        displayLabel: origin.displayLabel,
        formattedAddress: origin.formattedAddress,
        latitude: origin.latitude,
        longitude: origin.longitude,
        countryCode: origin.countryCode,
        countryName: origin.countryName,
        provider: 'development_approximation',
      ),
    ];
    for (int i = 1; i < steps; i++) {
      final t = i / steps;
      final lat = origin.latitude + (destination.latitude - origin.latitude) * t;
      final lng = origin.longitude + (destination.longitude - origin.longitude) * t;
      list.add(
        ConfirmedLocation(
          displayLabel: 'Approximate Point $i',
          formattedAddress: 'Approximate Waypoint',
          latitude: lat,
          longitude: lng,
          countryCode: origin.countryCode,
          countryName: origin.countryName,
          provider: 'development_approximation',
        ),
      );
    }
    list.add(
      ConfirmedLocation(
        displayLabel: destination.displayLabel,
        formattedAddress: destination.formattedAddress,
        latitude: destination.latitude,
        longitude: destination.longitude,
        countryCode: destination.countryCode,
        countryName: destination.countryName,
        provider: 'development_approximation',
      ),
    );
    return list;
  }
}

class BackendRoutingAdapter implements RoutingProvider {
  final dynamic apiClient;
  final RoutingProvider? fallbackAdapter;
  const BackendRoutingAdapter({this.apiClient, this.fallbackAdapter});

  @override
  Future<RouteResult> calculateRoute(ConfirmedLocation origin, ConfirmedLocation destination) async {
    final client = apiClient;
    if (client == null) {
      if (fallbackAdapter != null) {
        return fallbackAdapter!.calculateRoute(origin, destination);
      }
      throw const RoutingException('Routing requires an authenticated ApiClient or explicit test adapter.');
    }

    try {
      final res = await client.post('/routes/compute', {
        'origin': {'lat': origin.latitude, 'lon': origin.longitude},
        'destination': {'lat': destination.latitude, 'lon': destination.longitude},
      }, requireAuth: false);

      final distMeters = (res['distanceMeters'] as num).toDouble();
      final durationSecs = (res['durationSeconds'] as num).toDouble();
      final geoJson = res['geoJson'] as Map<String, dynamic>?;
      final coords = (geoJson?['coordinates'] as List<dynamic>?) ?? [];

      final polylinePoints = <ConfirmedLocation>[];
      for (int i = 0; i < coords.length; i++) {
        final pt = coords[i] as List;
        final lng = (pt[0] as num).toDouble();
        final lat = (pt[1] as num).toDouble();
        polylinePoints.add(
          ConfirmedLocation(
            displayLabel: i == 0
                ? origin.displayLabel
                : i == coords.length - 1
                    ? destination.displayLabel
                    : 'Waypoint $i',
            formattedAddress: 'Road Waypoint',
            latitude: lat,
            longitude: lng,
            countryCode: 'IN',
            countryName: 'India',
            provider: 'backend-production-router',
          ),
        );
      }

      if (polylinePoints.isNotEmpty) {
        return RouteResult(
          origin: origin,
          destination: destination,
          polylinePoints: polylinePoints,
          distanceMeters: distMeters,
          durationSeconds: durationSecs,
          provider: 'backend-production-router',
        );
      }
      throw const RoutingException('Backend routing service returned empty coordinates.');
    } catch (e) {
      if (e is RoutingException) rethrow;
      throw RoutingException('Failed to compute authoritative road route from backend: $e');
    }
  }
}
