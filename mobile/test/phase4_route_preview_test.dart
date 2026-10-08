import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shipdehop_mobile/core/external_directions_launcher.dart';
import 'package:shipdehop_mobile/core/routing_provider.dart';
import 'package:shipdehop_mobile/models/confirmed_location.dart';
import 'package:shipdehop_mobile/models/route_result.dart';
import 'package:shipdehop_mobile/widgets/route_preview_widget.dart';

class MockErrorRoutingProvider implements RoutingProvider {
  @override
  Future<RouteResult> calculateRoute(ConfirmedLocation origin, ConfirmedLocation destination) async {
    throw const RoutingException("We couldn't calculate the road route right now.");
  }
}

void main() {
  const mumbai = ConfirmedLocation(
    displayLabel: 'Mumbai, Maharashtra',
    formattedAddress: 'Mumbai, India',
    latitude: 19.0760,
    longitude: 72.8777,
    countryCode: 'IN',
  );

  const pune = ConfirmedLocation(
    displayLabel: 'Pune, Maharashtra',
    formattedAddress: 'Pune, India',
    latitude: 18.5204,
    longitude: 73.8567,
    countryCode: 'IN',
  );

  const doha = ConfirmedLocation(
    displayLabel: 'Doha, Qatar',
    formattedAddress: 'Doha, Qatar',
    latitude: 25.2854,
    longitude: 51.5310,
    countryCode: 'QA',
  );

  const lusail = ConfirmedLocation(
    displayLabel: 'Lusail, Qatar',
    formattedAddress: 'Lusail City, Qatar',
    latitude: 25.4200,
    longitude: 51.4900,
    countryCode: 'QA',
  );

  group('Phase 4 OsrmRoutingAdapter Real OSRM & Fallback Unit Tests', () {
    test('OsrmRoutingAdapter parses real OSRM GeoJSON response for Mumbai -> Pune', () async {
      final mockClient = MockClient((request) async {
        final sampleGeoJson = {
          'code': 'Ok',
          'routes': [
            {
              'distance': 148500.0,
              'duration': 9900.0,
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [72.8777, 19.0760],
                  [73.3000, 18.8000],
                  [73.8567, 18.5204],
                ],
              },
            }
          ],
        };
        return http.Response(jsonEncode(sampleGeoJson), 200);
      });

      final adapter = OsrmRoutingAdapter(httpClient: mockClient);
      final route = await adapter.calculateRoute(mumbai, pune);

      expect(route.provider, 'development_osrm_demo');
      expect(route.formattedDistance, '149 km');
      expect(route.formattedDuration, '2 hr 45 mins');
      expect(route.polylinePoints.length, 3);
      expect(route.polylinePoints.first.latitude, 19.0760);
      expect(route.polylinePoints.last.latitude, 18.5204);
    });

    test('OsrmRoutingAdapter parses real OSRM GeoJSON response for Doha -> Lusail', () async {
      final mockClient = MockClient((request) async {
        final sampleGeoJson = {
          'code': 'Ok',
          'routes': [
            {
              'distance': 22400.0,
              'duration': 1440.0,
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [51.5310, 25.2854],
                  [51.5100, 25.3500],
                  [51.4900, 25.4200],
                ],
              },
            }
          ],
        };
        return http.Response(jsonEncode(sampleGeoJson), 200);
      });

      final adapter = OsrmRoutingAdapter(httpClient: mockClient);
      final route = await adapter.calculateRoute(doha, lusail);

      expect(route.provider, 'development_osrm_demo');
      expect(route.formattedDistance, '22 km');
      expect(route.formattedDuration, '24 mins');
      expect(route.polylinePoints.length, 3);
    });

    test('DevelopmentApproximationAdapter returns clearly labelled fallback estimate', () async {
      const adapter = DevelopmentApproximationAdapter();
      final route = await adapter.calculateRoute(mumbai, pune);

      expect(route.provider, 'development_approximation');
      expect(route.distanceMeters, greaterThan(100000));
      expect(route.polylinePoints.first.provider, 'development_approximation');
    });
  });

  group('Phase 4 ExternalDirectionsLauncher URL Generation Tests', () {
    test('Generates valid directions URLs for all supported navigation providers', () {
      final googleUrl = ExternalDirectionsLauncher.getDirectionsUrl(
        provider: NavigationProvider.googleMaps,
        origin: mumbai,
        destination: pune,
      );
      expect(googleUrl, contains('google.com/maps/dir'));

      final appleUrl = ExternalDirectionsLauncher.getDirectionsUrl(
        provider: NavigationProvider.appleMaps,
        origin: mumbai,
        destination: pune,
      );
      expect(appleUrl, contains('maps.apple.com'));

      final wazeUrl = ExternalDirectionsLauncher.getDirectionsUrl(
        provider: NavigationProvider.waze,
        origin: mumbai,
        destination: pune,
      );
      expect(wazeUrl, contains('waze.com/ul'));

      final osmUrl = ExternalDirectionsLauncher.getDirectionsUrl(
        provider: NavigationProvider.openStreetMap,
        origin: mumbai,
        destination: pune,
      );
      expect(osmUrl, contains('openstreetmap.org/directions'));
    });
  });

  group('Phase 4 RoutePreviewWidget UI & Attribution Tests', () {
    testWidgets('Renders OSRM road route preview with dynamic attribution', (tester) async {
      final mockClient = MockClient((request) async {
        final sample = {
          'code': 'Ok',
          'routes': [
            {
              'distance': 148500.0,
              'duration': 9900.0,
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [72.8777, 19.0760],
                  [73.8567, 18.5204],
                ],
              },
            }
          ],
        };
        return http.Response(jsonEncode(sample), 200);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RoutePreviewWidget(
                origin: mumbai,
                destination: pune,
                routingProvider: OsrmRoutingAdapter(httpClient: mockClient),
                onRouteConfirmed: (_) {},
                onEditOrigin: () {},
                onEditDestination: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Journey Route Preview'), findsOneWidget);
      expect(find.text('Mumbai, Maharashtra'), findsOneWidget);
      expect(find.text('Pune, Maharashtra'), findsOneWidget);
      expect(find.text('149 km'), findsOneWidget);
      expect(find.text('2 hr 45 mins'), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors • OSRM Demo'), findsOneWidget);
    });

    testWidgets('Renders failure state gracefully with retry action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoutePreviewWidget(
              origin: mumbai,
              destination: pune,
              routingProvider: MockErrorRoutingProvider(),
              onRouteConfirmed: (_) {},
              onEditOrigin: () {},
              onEditDestination: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("We couldn't calculate the road route right now."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
