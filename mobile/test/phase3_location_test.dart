import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/api_client.dart';
import 'package:shipdehop_mobile/core/geocoding_provider.dart';
import 'package:shipdehop_mobile/core/location_service.dart';
import 'package:shipdehop_mobile/models/confirmed_location.dart';
import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/screens/hopship_screen.dart';
import 'package:shipdehop_mobile/screens/publish_route_screen.dart';
import 'package:shipdehop_mobile/widgets/location_map_confirmation_widget.dart';
import 'package:shipdehop_mobile/widgets/location_picker.dart';

class MockLocationApiClient extends Fake implements ApiClient {
  @override
  Future<dynamic> get(String path, {bool requireAuth = true}) async => <dynamic>[];

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool requireAuth = true,
  }) async => <String, dynamic>{};
}

class ErrorLocationService implements LocationService {
  @override
  Future<ConfirmedLocation> getCurrentLocation() async {
    throw const LocationServiceException(
      'Location access is off. Search for an address instead.',
    );
  }
}

Future<void> searchLocation(WidgetTester tester, String query) async {
  final field = find.byKey(const Key('location_search_field'));
  expect(field, findsOneWidget);
  await tester.enterText(field, query);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder target, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps && target.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('Phase 3 Shared Location Domain & Provider Unit Tests', () {
    test('ConfirmedLocation retains internal coordinates and country metadata', () {
      const loc = ConfirmedLocation(
        displayLabel: 'Mumbai, Maharashtra',
        formattedAddress: 'Mumbai, Maharashtra, India',
        latitude: 19.0760,
        longitude: 72.8777,
        countryCode: 'IN',
        countryName: 'India',
        locality: 'Mumbai',
        administrativeArea: 'Maharashtra',
      );
      expect(loc.displayLabel, 'Mumbai, Maharashtra');
      expect(loc.countryCode, 'IN');
      expect(loc.countryName, 'India');
      expect(loc.latitude, 19.0760);
      expect(loc.longitude, 72.8777);
      final revived = ConfirmedLocation.fromJson(loc.toJson());
      expect(revived.countryCode, 'IN');
      expect(revived.countryName, 'India');
    });

    test('DevelopmentGeocodingAdapter exposes India places only', () async {
      const adapter = DevelopmentGeocodingAdapter();
      final popular = await adapter.search('');
      expect(popular, isNotEmpty);
      expect(popular.every((place) => place.countryCode == 'IN'), isTrue);
      expect(await adapter.search('Doha'), isEmpty);
      expect(await adapter.search('Dubai'), isEmpty);

      final results = await adapter.search('Mumbai');
      expect(results, isNotEmpty);
      expect(results.first.countryCode, 'IN');
      expect(results.first.locality, 'Mumbai');
      final rev = await adapter.reverseGeocode(19.0760, 72.8777);
      expect(rev.locality, 'Mumbai');
    });
  });

  group('Phase 3 LocationPicker Widget Tests', () {
    testWidgets('LocationPicker displays title and India searchable results', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationPicker(
              title: 'Pickup Location',
              geocodingProvider: const DevelopmentGeocodingAdapter(),
              locationService: const DefaultLocationService(),
              onLocationConfirmed: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pickup Location'), findsOneWidget);
      expect(find.text('Search city, area, landmark or address'), findsOneWidget);

      await tester.tap(find.byType(LocationPicker));
      await tester.pumpAndSettle();
      expect(find.text('Use my current location'), findsOneWidget);
      expect(find.text('INDIA'), findsOneWidget);
      expect(find.text('Popular places in India'), findsOneWidget);

      await searchLocation(tester, 'Mumbai');
      expect(find.text('Search results'), findsOneWidget);
      expect(find.text('Mumbai, Maharashtra'), findsOneWidget);
    });

    testWidgets('Permission denial displays graceful consumer message without crashing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationPicker(
              title: 'Pickup Location',
              geocodingProvider: const DevelopmentGeocodingAdapter(),
              locationService: ErrorLocationService(),
              onLocationConfirmed: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(LocationPicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      expect(
        find.text('Location access is off. Search for an address instead.'),
        findsOneWidget,
      );
    });

    testWidgets('Selecting India search result opens Map Confirmation View', (tester) async {
      ConfirmedLocation? confirmedResult;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationPicker(
              title: 'Pickup Location',
              geocodingProvider: const DevelopmentGeocodingAdapter(),
              locationService: const DefaultLocationService(),
              onLocationConfirmed: (loc) => confirmedResult = loc,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(LocationPicker));
      await tester.pumpAndSettle();
      await searchLocation(tester, 'Mumbai');
      await tester.tap(find.text('Mumbai, Maharashtra'));

      final mapView = find.byType(LocationMapConfirmationWidget);
      await pumpUntilFound(tester, mapView);
      expect(mapView, findsOneWidget);
      expect(find.text('Confirm Location Pin'), findsOneWidget);
      expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);

      await tester.tap(find.text('Confirm Location'));
      for (var i = 0; i < 20 && confirmedResult == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(confirmedResult, isNotNull);
      expect(confirmedResult!.displayLabel, contains('Mumbai'));
      expect(confirmedResult!.countryCode, 'IN');
    });
  });

  group('Phase 3 Form Integration & Absence of Raw Coordinate Fields', () {
    testWidgets('HopShipScreen uses LocationPicker and contains NO raw latitude/longitude inputs', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockLocationApiClient()),
          ],
          child: const MaterialApp(
            home: HopShipScreen(
              prefilledPickup: 'Mumbai',
              prefilledDropoff: 'Pune',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pickup Location'), findsOneWidget);
      expect(find.text('Drop-off Location'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Latitude'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Longitude'), findsNothing);
    });

    testWidgets('PublishRouteScreen uses LocationPicker and contains NO raw lat/lon inputs', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockLocationApiClient()),
          ],
          child: const MaterialApp(home: PublishRouteScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Journey Origin'), findsOneWidget);
      expect(find.text('Journey Destination'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Origin Lat'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Origin Lon'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Destination Lat'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Destination Lon'), findsNothing);
    });
  });
}
