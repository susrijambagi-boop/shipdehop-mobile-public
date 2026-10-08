import 'confirmed_location.dart';

class RouteResult {
  const RouteResult({
    required this.origin,
    required this.destination,
    required this.polylinePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    this.provider = 'osrm_development_adapter',
  });

  final ConfirmedLocation origin;
  final ConfirmedLocation destination;
  final List<ConfirmedLocation> polylinePoints;
  final double distanceMeters;
  final double durationSeconds;
  final String provider;

  double get distanceKm => distanceMeters / 1000.0;

  String get formattedDistance {
    if (distanceKm >= 10) {
      return '${distanceKm.toStringAsFixed(0)} km';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  String get formattedDuration {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) {
      return '$minutes mins';
    }
    final hours = minutes ~/ 60;
    final remMinutes = minutes % 60;
    if (remMinutes == 0) {
      return '$hours hr${hours > 1 ? 's' : ''}';
    }
    return '$hours hr $remMinutes mins';
  }

  Map<String, dynamic> toJson() => {
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        'polylinePoints': polylinePoints.map((p) => p.toJson()).toList(),
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'provider': provider,
      };

  factory RouteResult.fromJson(Map<String, dynamic> json) => RouteResult(
        origin: ConfirmedLocation.fromJson(json['origin'] as Map<String, dynamic>),
        destination: ConfirmedLocation.fromJson(json['destination'] as Map<String, dynamic>),
        polylinePoints: (json['polylinePoints'] as List)
            .cast<Map<String, dynamic>>()
            .map(ConfirmedLocation.fromJson)
            .toList(),
        distanceMeters: (json['distanceMeters'] as num).toDouble(),
        durationSeconds: (json['durationSeconds'] as num).toDouble(),
        provider: json['provider']?.toString() ?? 'osrm_development_adapter',
      );
}
