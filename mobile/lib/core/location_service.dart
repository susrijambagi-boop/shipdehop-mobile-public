import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'geocoding_provider.dart';
import 'launch_market.dart';
import '../models/confirmed_location.dart';

enum LocationErrorType {
  insecureContext,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeoutOrUnavailable,
  unsupportedRegion,
  unknown,
}

class LocationServiceException implements Exception {
  const LocationServiceException(
    this.message, {
    this.type = LocationErrorType.unknown,
  });

  final String message;
  final LocationErrorType type;

  @override
  String toString() => message;
}

abstract class LocationService {
  Future<ConfirmedLocation> getCurrentLocation();
}

class DefaultLocationService implements LocationService {
  const DefaultLocationService({
    this.geocodingProvider = const BackendGeocodingAdapter(),
  });

  final GeocodingProvider geocodingProvider;

  /// Detects if the current runtime is an insecure web context (e.g. HTTP over LAN).
  /// Browsers strictly forbid Geolocation API on insecure origins.
  static bool get isInsecureWebContext {
    if (!kIsWeb) return false;
    final uri = Uri.base;
    if (uri.scheme == 'http') {
      final host = uri.host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1') {
        return false;
      }
      return true;
    }
    return false;
  }

  @override
  Future<ConfirmedLocation> getCurrentLocation() async {
    if (isInsecureWebContext) {
      throw const LocationServiceException(
        'Current location needs a secure HTTPS connection in the browser. Open the HTTPS ShipdeHop test URL or search for an address.',
        type: LocationErrorType.insecureContext,
      );
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const LocationServiceException(
          'Location services are turned off. Enable location access and try again.',
          type: LocationErrorType.serviceDisabled,
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const LocationServiceException(
          'Location permission was denied. Allow location access and try again.',
          type: LocationErrorType.permissionDenied,
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const LocationServiceException(
          'Location permission is blocked. Enable it in your browser or device settings.',
          type: LocationErrorType.permissionDeniedForever,
        );
      }

      final Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        throw const LocationServiceException(
          'Could not fetch your current location. Search for an address instead.',
          type: LocationErrorType.timeoutOrUnavailable,
        );
      }

      // Reject outside-market GPS before any route can be created from it.
      if (!LaunchMarket.containsCoordinates(
        position.latitude,
        position.longitude,
      )) {
        throw const LocationServiceException(
          LaunchMarket.unsupportedMessage,
          type: LocationErrorType.unsupportedRegion,
        );
      }

      final loc = await geocodingProvider.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      if (!LaunchMarket.isSupportedLocation(loc)) {
        throw const LocationServiceException(
          LaunchMarket.unsupportedMessage,
          type: LocationErrorType.unsupportedRegion,
        );
      }

      return ConfirmedLocation(
        displayLabel: 'Current Location (${loc.locality ?? loc.displayLabel})',
        formattedAddress: loc.formattedAddress,
        latitude: position.latitude,
        longitude: position.longitude,
        countryCode: LaunchMarket.countryCode,
        countryName: LaunchMarket.countryName,
        locality: loc.locality,
        administrativeArea: loc.administrativeArea,
        postalCode: loc.postalCode,
        provider: 'device_current_location',
      );
    } on LocationServiceException {
      rethrow;
    } catch (_) {
      throw const LocationServiceException(
        'Could not fetch your current location. Search for an address instead.',
        type: LocationErrorType.unknown,
      );
    }
  }
}