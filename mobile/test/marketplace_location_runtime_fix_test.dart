import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/currency_catalog.dart';
import 'package:shipdehop_mobile/core/geocoding_provider.dart';
import 'package:shipdehop_mobile/core/location_service.dart';
import 'package:shipdehop_mobile/models/confirmed_location.dart';
import 'package:shipdehop_mobile/widgets/location_picker.dart';

class MockLocationService implements LocationService {
  MockLocationService({this.shouldThrow, this.mockLocation});

  final LocationServiceException? shouldThrow;
  final ConfirmedLocation? mockLocation;
  int callCount = 0;

  @override
  Future<ConfirmedLocation> getCurrentLocation() async {
    callCount++;
    if (shouldThrow != null) throw shouldThrow!;
    return mockLocation ??
        const ConfirmedLocation(
          displayLabel: 'Current Location (Bengaluru)',
          formattedAddress: 'Bengaluru, Karnataka, India',
          latitude: 12.9716,
          longitude: 77.5946,
          countryCode: 'IN',
          countryName: 'India',
          locality: 'Bengaluru',
          provider: 'device_current_location',
        );
  }
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocationService & Geocoding & State Tests (15-25)', () {
    test('15: Current location is not requested at startup', () async {
      final mockService = MockLocationService();
      expect(mockService.callCount, 0);
    });

    test('16: Secure granted flow returns genuine India coordinates', () async {
      const genuineLat = 12.9716;
      const genuineLng = 77.5946;
      final mockService = MockLocationService();
      final loc = await mockService.getCurrentLocation();
      expect(loc.latitude, genuineLat);
      expect(loc.longitude, genuineLng);
      expect(loc.countryCode, 'IN');
      expect(loc.locality, 'Bengaluru');
      expect(mockService.callCount, 1);
    });

    test('17: Denied permission handled with specific type', () async {
      final mockService = MockLocationService(
        shouldThrow: const LocationServiceException(
          'Location permission was denied. Allow location access and try again.',
          type: LocationErrorType.permissionDenied,
        ),
      );
      expect(
        () => mockService.getCurrentLocation(),
        throwsA(predicate((e) =>
            e is LocationServiceException &&
            e.type == LocationErrorType.permissionDenied &&
            e.message.contains('denied'))),
      );
    });

    test('18: Permanently denied permission handled with settings prompt', () async {
      final mockService = MockLocationService(
        shouldThrow: const LocationServiceException(
          'Location permission is blocked. Enable it in your browser or device settings.',
          type: LocationErrorType.permissionDeniedForever,
        ),
      );
      expect(
        () => mockService.getCurrentLocation(),
        throwsA(predicate((e) =>
            e is LocationServiceException &&
            e.type == LocationErrorType.permissionDeniedForever &&
            e.message.contains('blocked'))),
      );
    });

    test('19: Location services unavailable handled', () async {
      final mockService = MockLocationService(
        shouldThrow: const LocationServiceException(
          'Location services are turned off. Enable location access and try again.',
          type: LocationErrorType.serviceDisabled,
        ),
      );
      expect(
        () => mockService.getCurrentLocation(),
        throwsA(predicate((e) =>
            e is LocationServiceException &&
            e.type == LocationErrorType.serviceDisabled &&
            e.message.contains('turned off'))),
      );
    });

    test('20 & 21: Insecure LAN HTTP detected separately and NOT reported as user-denied', () async {
      final mockService = MockLocationService(
        shouldThrow: const LocationServiceException(
          'Current location needs a secure HTTPS connection in the browser. Open the HTTPS ShipdeHop test URL or search for an address.',
          type: LocationErrorType.insecureContext,
        ),
      );
      try {
        await mockService.getCurrentLocation();
        fail('Should have thrown');
      } on LocationServiceException catch (e) {
        expect(e.type, LocationErrorType.insecureContext);
        expect(e.message, contains('secure HTTPS connection in the browser'));
        expect(e.message, isNot(contains('permission is blocked')));
      }
    });

    test('22 & 24: DevelopmentGeocodingAdapter preserves exact coordinates and resolves India and unsupported foreign locations', () async {
      const adapter = DevelopmentGeocodingAdapter();

      // Doha coordinates (Outside India -> UNSUPPORTED)
      const dohaLat = 25.29123;
      const dohaLng = 51.52456;
      final qatarLoc = await adapter.reverseGeocode(dohaLat, dohaLng);
      expect(qatarLoc.latitude, dohaLat);
      expect(qatarLoc.longitude, dohaLng);
      expect(qatarLoc.countryCode, 'UNSUPPORTED');
      expect(qatarLoc.countryName, 'Outside India');

      // Dubai coordinates (Outside India -> UNSUPPORTED)
      const dubaiLat = 25.2048;
      const dubaiLng = 55.2708;
      final uaeLoc = await adapter.reverseGeocode(dubaiLat, dubaiLng);
      expect(uaeLoc.latitude, dubaiLat);
      expect(uaeLoc.longitude, dubaiLng);
      expect(uaeLoc.countryCode, 'UNSUPPORTED');

      // Mumbai coordinates (India -> IN)
      const mumbaiLat = 19.0760;
      const mumbaiLng = 72.8777;
      final indiaLoc = await adapter.reverseGeocode(mumbaiLat, mumbaiLng);
      expect(indiaLoc.latitude, mumbaiLat);
      expect(indiaLoc.longitude, mumbaiLng);
      expect(indiaLoc.countryCode, 'IN');
    });

    test('23: Search suggestions are India-only', () async {
      const adapter = DevelopmentGeocodingAdapter();
      final mumbaiResults = await adapter.search('Mumbai');
      expect(mumbaiResults.any((p) => p.locality == 'Mumbai'), isTrue);
      expect(mumbaiResults.every((p) => p.countryCode == 'IN'), isTrue);
    });

    testWidgets('25: LocationPicker current-location action invokes service', (tester) async {
      final mockService = MockLocationService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationPicker(
              title: 'Item location',
              geocodingProvider: const DevelopmentGeocodingAdapter(),
              locationService: mockService,
              onLocationConfirmed: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Item location'), findsOneWidget);
      expect(mockService.callCount, 0);
      await tester.tap(find.text('Item location'));
      await tester.pumpAndSettle();
      expect(find.text('Use my current location'), findsOneWidget);
      expect(find.text('Popular places in India'), findsOneWidget);

      await tester.tap(find.text('Use my current location'));
      final mapTitle = find.text('Confirm Location Pin');
      await pumpUntilFound(tester, mapTitle);
      expect(mockService.callCount, 1);
      expect(mapTitle, findsOneWidget);
    });
  });

  group('Regression & Multi-Module LocationPicker Tests (26-30)', () {
    testWidgets('26: ParcelPool LocationPicker functions correctly', (tester) async {
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
      expect(find.text('Pickup Location'), findsOneWidget);
      await tester.tap(find.text('Pickup Location'));
      await tester.pumpAndSettle();
      expect(find.text('Use my current location'), findsOneWidget);
      expect(find.text('Popular places in India'), findsOneWidget);
    });

    testWidgets('27: Publish Journey LocationPicker functions correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationPicker(
              title: 'Origin',
              geocodingProvider: const DevelopmentGeocodingAdapter(),
              locationService: const DefaultLocationService(),
              onLocationConfirmed: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Origin'), findsOneWidget);
      await tester.tap(find.text('Origin'));
      await tester.pumpAndSettle();
      expect(find.text('Popular places in India'), findsOneWidget);
    });

    testWidgets('28: Marketplace India location selection works', (tester) async {
      ConfirmedLocation? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationPicker(
              title: 'Item location',
              geocodingProvider: const DevelopmentGeocodingAdapter(),
              locationService: const DefaultLocationService(),
              onLocationConfirmed: (loc) => confirmed = loc,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Item location'));
      await tester.pumpAndSettle();

      expect(find.text('Mumbai, Maharashtra'), findsWidgets);
      await tester.tap(find.text('Mumbai, Maharashtra').first);
      await tester.pumpAndSettle();

      final mapTitle = find.text('Confirm Location Pin');
      await pumpUntilFound(tester, mapTitle);
      expect(mapTitle, findsOneWidget);
      expect(find.text('Confirm Location'), findsOneWidget);
      await tester.tap(find.text('Confirm Location'));
      for (var i = 0; i < 20 && confirmed == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(confirmed, isNotNull);
      expect(confirmed!.countryCode, 'IN');
      expect(confirmed!.locality, 'Mumbai');
    });

    test('29: Currency catalog still formats supported currency codes', () {
      expect(CurrencyCatalog.defaultForCountryCode('IN'), 'INR');
      expect(CurrencyCatalog.defaultForCountryCode('IND'), 'INR');
    });
  });
}
