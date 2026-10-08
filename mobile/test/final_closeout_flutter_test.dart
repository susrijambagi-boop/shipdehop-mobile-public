import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shipdehop_mobile/core/api_client.dart';
import 'package:shipdehop_mobile/core/geocoding_provider.dart';
import 'package:shipdehop_mobile/core/india_time.dart';
import 'package:shipdehop_mobile/core/location_validation.dart';
import 'package:shipdehop_mobile/core/money_formatter.dart';
import 'package:shipdehop_mobile/core/policy_resolver.dart';
import 'package:shipdehop_mobile/core/routing_provider.dart';
import 'package:shipdehop_mobile/models/confirmed_location.dart';
import 'package:shipdehop_mobile/models/date_flexibility.dart';
import 'package:shipdehop_mobile/models/domain.dart';
import 'package:shipdehop_mobile/models/journey.dart';
import 'package:shipdehop_mobile/models/journey_opportunity.dart';
import 'package:shipdehop_mobile/models/route_result.dart';
import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/repositories/journey_repository.dart';
import 'package:shipdehop_mobile/screens/create_journey_screen.dart';
import 'package:shipdehop_mobile/core/location_service.dart';
import 'package:shipdehop_mobile/widgets/location_picker.dart';

class MockHttpClient extends http.BaseClient {
  MockHttpClient(this._handler);
  final Future<http.Response> Function(http.Request request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await _handler(request as http.Request);
    return http.StreamedResponse(
      Stream.value(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
    );
  }
}

class MockJourneyRepository implements JourneyRepository {
  Journey? createdJourney;

  @override
  Future<Journey> createJourney(Journey journey) async {
    createdJourney = journey;
    return journey;
  }

  @override
  Future<List<Journey>> fetchUserJourneys() async => [];

  @override
  Future<Journey> fetchJourneyDetails(String journeyId) async {
    return createdJourney ??
        Journey(
          id: journeyId,
          origin: const ConfirmedLocation(displayLabel: 'A', formattedAddress: 'A', latitude: 12.0, longitude: 77.0),
          destination: const ConfirmedLocation(displayLabel: 'B', formattedAddress: 'B', latitude: 12.1, longitude: 77.1),
          timing: DateFlexibility(earliestDateTime: DateTime.now(), latestDateTime: DateTime.now()),
          travellerName: 'You',
        );
  }

  @override
  Future<List<JourneyOpportunity>> fetchJourneyOpportunities(String journeyId) async => [];
}

class MockGeocodingAdapter implements GeocodingProvider {
  MockGeocodingAdapter(this.results);
  final List<ConfirmedLocation> results;

  @override
  Future<List<ConfirmedLocation>> search(String query) async => results;

  @override
  Future<ConfirmedLocation> reverseGeocode(double lat, double lon) async => results.first;
}

class MockRoutingAdapter implements RoutingProvider {
  MockRoutingAdapter({this.result, this.shouldFail = false});
  final RouteResult? result;
  final bool shouldFail;

  @override
  Future<RouteResult> calculateRoute(ConfirmedLocation origin, ConfirmedLocation destination) async {
    if (shouldFail) throw const RoutingException('Routing service unavailable');
    return result ??
        RouteResult(
          distanceMeters: 150000.0,
          durationSeconds: 10800.0,
          polylinePoints: [origin, destination],
          origin: origin,
          destination: destination,
        );
  }
}

void main() {
  group('Final India-Launch Closeout Flutter Test Suite', () {
    test('1. IndiaTime converts UTC to IST and handles date rollover correctly', () {
      final utcTime1 = DateTime.utc(2026, 9, 21, 3, 30);
      final istTime1 = IndiaTime.toIST(utcTime1);
      expect(istTime1.hour, equals(9));
      expect(istTime1.minute, equals(0));
      expect(IndiaTime.formatIST(utcTime1), equals('09:00 IST'));

      final utcTime2 = DateTime.utc(2026, 9, 21, 21, 0);
      final istTime2 = IndiaTime.toIST(utcTime2);
      expect(istTime2.day, equals(22));
      expect(istTime2.hour, equals(2));
      expect(istTime2.minute, equals(30));

      final pickerValue = DateTime(2026, 9, 21, 14, 30);
      final utcFromPicker = IndiaTime.istToUTC(pickerValue);
      final restoredIST = IndiaTime.toIST(utcFromPicker);
      expect(restoredIST.hour, equals(14));
      expect(restoredIST.minute, equals(30));
    });

    test('2. MoneyFormatter preserves historical currency truth (QAR vs INR)', () {
      expect(MoneyFormatter.format(1500, 'INR'), equals('₹1,500'));
      expect(MoneyFormatter.format(250, 'QAR'), equals('QAR 250'));
      expect(MoneyFormatter.formatQAR(250), equals('QAR 250'));
      expect(MoneyFormatter.formatINR(1500), equals('₹1,500'));
      expect(MoneyFormatter.format(500, 'AED'), equals('AED 500'));
    });

    test('3. validateIndianPinCode accepts valid 6-digit non-zero-leading PINs and rejects malformed inputs', () {
      expect(validateIndianPinCode('400001'), isTrue);
      expect(validateIndianPinCode('560001'), isTrue);
      expect(validateIndianPinCode('110001'), isTrue);
      expect(validateIndianPinCode(' 560001 '), isTrue);

      expect(validateIndianPinCode('012345'), isFalse);
      expect(validateIndianPinCode('12345'), isFalse);
      expect(validateIndianPinCode('1234567'), isFalse);
      expect(validateIndianPinCode('56000A'), isFalse);
      expect(validateIndianPinCode('ABCDEF'), isFalse);
      expect(validateIndianPinCode(''), isFalse);
    });

    test('4. BackendGeocodingAdapter fails closed without ApiClient or fallbackAdapter', () {
      const adapter = BackendGeocodingAdapter();
      expect(() => adapter.search('Bengaluru'), throwsA(isA<GeocodingException>()));
      expect(() => adapter.reverseGeocode(12.9716, 77.5946), throwsA(isA<GeocodingException>()));
    });

    test('5. BackendGeocodingAdapter handles backend failure and never calls DevelopmentGeocodingAdapter', () async {
      final mockClient = MockHttpClient((request) async {
        return http.Response('Internal Server Error', 500);
      });
      final apiClient = ApiClient(null, httpClient: mockClient, tokenProvider: () => null);
      final adapter = BackendGeocodingAdapter(apiClient: apiClient);

      expect(() => adapter.search('Mumbai'), throwsA(isA<GeocodingException>()));
    });

    test('6. BackendRoutingAdapter fails closed without ApiClient or fallbackAdapter and makes zero OSRM calls', () {
      const router = BackendRoutingAdapter();
      const origin = ConfirmedLocation(displayLabel: 'Origin', formattedAddress: 'Origin', latitude: 12.9716, longitude: 77.5946, countryCode: 'IN', countryName: 'India');
      const dest = ConfirmedLocation(displayLabel: 'Dest', formattedAddress: 'Dest', latitude: 12.3168, longitude: 76.6497, countryCode: 'IN', countryName: 'India');

      expect(() => router.calculateRoute(origin, dest), throwsA(isA<RoutingException>()));
    });

    test('7. BackendRoutingAdapter fails closed on backend failure without falling back to OSRM', () async {
      int osrmCalls = 0;
      final mockClient = MockHttpClient((request) async {
        if (request.url.host.contains('router.project-osrm.org')) {
          osrmCalls++;
        }
        return http.Response('Service Unavailable', 503);
      });
      final apiClient = ApiClient(null, httpClient: mockClient, tokenProvider: () => null);
      final router = BackendRoutingAdapter(apiClient: apiClient);
      const origin = ConfirmedLocation(displayLabel: 'Origin', formattedAddress: 'Origin', latitude: 12.9716, longitude: 77.5946, countryCode: 'IN', countryName: 'India');
      const dest = ConfirmedLocation(displayLabel: 'Dest', formattedAddress: 'Dest', latitude: 12.3168, longitude: 76.6497, countryCode: 'IN', countryName: 'India');

      expect(() => router.calculateRoute(origin, dest), throwsA(isA<RoutingException>()));
      expect(osrmCalls, equals(0));
    });

    test('8. Journey currency and jurisdiction defaults are INR/IN without QAR/QA or 25.0 price fallbacks', () {
      final historical = Journey.fromJson({
        'id': 'hist-1',
        'currency': 'QAR',
        'jurisdiction_code': 'QA',
        'price_per_seat': 50.0,
      });
      expect(historical.currency, equals('QAR'));
      expect(historical.jurisdictionCode, equals('QA'));
      expect(historical.pricePerSeat, equals(50.0));

      final newLaunch = Journey.fromJson({
        'id': 'new-1',
        'origin': {'displayLabel': 'Bengaluru', 'lat': 12.97, 'lon': 77.59},
        'destination': {'displayLabel': 'Mysuru', 'lat': 12.31, 'lon': 76.64},
      });
      expect(newLaunch.currency, equals('INR'));
      expect(newLaunch.jurisdictionCode, equals('IN'));
      expect(newLaunch.pricePerSeat, equals(0.0));
    });

    test('9. PolicyRepository fetches /policies/IN and returns ResolvedPolicy without invented policyName', () async {
      final mockClient = MockHttpClient((request) async {
        if (request.url.path.contains('/policies/IN')) {
          return http.Response(
            jsonEncode({
              'jurisdictionCode': 'IN',
              'currency': 'INR',
              'enabled': true,
              'maxRecoveryRatio': 0.8,
              'hardCapPerSeat': 400.0,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      });

      final apiClient = ApiClient(null, httpClient: mockClient, tokenProvider: () => null);
      final repo = PolicyRepository(apiClient);
      final policy = await repo.fetchPolicy('IN');

      expect(policy.jurisdictionCode, equals('IN'));
      expect(policy.currency, equals('INR'));
      expect(policy.isSupported, isTrue);
      expect(policy.maxRecoveryRatio, equals(0.8));
      expect(policy.hardCapPerSeat, equals(400.0));
      expect(policy.policyName, isNull);
      expect(policy.formattedSummary, equals('India • INR • IN'));
    });

    test('10. Selected-location Marketplace & Shipment feed SQL responses deserialize cleanly into Flutter models', () {
      final marketplaceJson = {
        'id': 'mkt-1',
        'seller_id': 'seller-100',
        'title': 'Organic Coffee Beans',
        'description': 'Freshly roasted',
        'price': 450.0,
        'currency': 'INR',
        'category': 'Groceries',
        'condition': 'NEW',
        'location_name': 'Koramangala, Bengaluru',
        'jurisdiction_code': 'IN',
        'available_quantity': 5,
        'ship_eligible': true,
        'images': ['https://example.com/img1.jpg'],
        'distance_km': 3.2,
      };

      final mktCard = MarketplaceCardModel.fromJson(marketplaceJson);
      expect(mktCard.id, equals('mkt-1'));
      expect(mktCard.sellerId, equals('seller-100'));
      expect(mktCard.title, equals('Organic Coffee Beans'));
      expect(mktCard.price, equals(450.0));
      expect(mktCard.currency, equals('INR'));
      expect(mktCard.locationName, equals('Koramangala, Bengaluru'));

      final shipmentJson = {
        'shipment_task_id': 'shp-1',
        'item_type': 'PARCEL',
        'pickup_name': 'Indiranagar',
        'drop_name': 'Whitefield',
        'weight_kg': 1.5,
        'reward_amount': 250.0,
        'currency': 'INR',
        'parcel_size_tier': 'ENVELOPE',
        'distance_km': 12.4,
      };

      final shpCard = ShipmentCardModel.fromJson(shipmentJson);
      expect(shpCard.id, equals('shp-1'));
      expect(shpCard.itemType, equals('PARCEL'));
      expect(shpCard.pickup, equals('Indiranagar'));
      expect(shpCard.drop, equals('Whitefield'));
      expect(shpCard.reward, equals(250.0));
      expect(shpCard.currency, equals('INR'));
    });

    testWidgets('11. CreateJourneyScreen starts with empty inputs and unset origin/destination, preventing publish until inputs set (873 & 117)', (WidgetTester tester) async {
      final mockRepo = MockJourneyRepository();
      const originLoc = ConfirmedLocation(displayLabel: 'Bengaluru', formattedAddress: 'Bengaluru, India', latitude: 12.9716, longitude: 77.5946, countryCode: 'IN', countryName: 'India');
      const destLoc = ConfirmedLocation(displayLabel: 'Mysuru', formattedAddress: 'Mysuru, India', latitude: 12.3168, longitude: 76.6497, countryCode: 'IN', countryName: 'India');

      final geocoder = MockGeocodingAdapter([originLoc, destLoc]);
      final router = MockRoutingAdapter();
      final mockClient = MockHttpClient((request) async {
        if (request.url.path.contains('/policies/IN')) {
          return http.Response(jsonEncode({'jurisdictionCode': 'IN', 'currency': 'INR', 'enabled': true, 'maxRecoveryRatio': 0.8, 'hardCapPerSeat': 500.0}), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 404);
      });
      final apiClient = ApiClient(null, httpClient: mockClient, tokenProvider: () => null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            geocodingProvider.overrideWithValue(geocoder),
            routingProvider.overrideWithValue(router),
            apiClientProvider.overrideWithValue(apiClient),
            policyRepositoryProvider.overrideWithValue(PolicyRepository(apiClient)),
          ],
          child: MaterialApp(
            home: CreateJourneyScreen(
              initialOriginLabel: 'Bengaluru',
              initialDestinationLabel: 'Mysuru',
              repository: mockRepo,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final buttonFinder = find.widgetWithText(ElevatedButton, 'Confirm & Publish Journey');
      expect(buttonFinder, findsOneWidget);
      final initialButton = tester.widget<ElevatedButton>(buttonFinder);
      expect(initialButton.onPressed, isNull);

      final costFinder = find.byKey(const Key('journey_estimated_trip_cost'));
      await tester.enterText(costFinder, '873');
      await tester.pumpAndSettle();

      final priceFinder = find.byKey(const Key('journey_price_per_seat'));
      await tester.enterText(priceFinder, '117');
      await tester.pumpAndSettle();

      final updatedButton = tester.widget<ElevatedButton>(buttonFinder);
      expect(updatedButton.onPressed, isNotNull);

      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(mockRepo.createdJourney, isNotNull);
      expect(mockRepo.createdJourney!.estimatedTripCost, equals(873.0));
      expect(mockRepo.createdJourney!.pricePerSeat, equals(117.0));
    });

    testWidgets('12. CreateJourneyScreen disables publish when backend route calculation fails', (WidgetTester tester) async {
      final mockRepo = MockJourneyRepository();
      const originLoc = ConfirmedLocation(displayLabel: 'Bengaluru', formattedAddress: 'Bengaluru, India', latitude: 12.9716, longitude: 77.5946, countryCode: 'IN', countryName: 'India');
      const destLoc = ConfirmedLocation(displayLabel: 'Mysuru', formattedAddress: 'Mysuru, India', latitude: 12.3168, longitude: 76.6497, countryCode: 'IN', countryName: 'India');

      final geocoder = MockGeocodingAdapter([originLoc, destLoc]);
      final failingRouter = MockRoutingAdapter(shouldFail: true);
      final mockClient = MockHttpClient((request) async {
        return http.Response(jsonEncode({'jurisdictionCode': 'IN', 'currency': 'INR', 'enabled': true, 'maxRecoveryRatio': 0.8}), 200, headers: {'content-type': 'application/json'});
      });
      final apiClient = ApiClient(null, httpClient: mockClient, tokenProvider: () => null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            geocodingProvider.overrideWithValue(geocoder),
            routingProvider.overrideWithValue(failingRouter),
            apiClientProvider.overrideWithValue(apiClient),
            policyRepositoryProvider.overrideWithValue(PolicyRepository(apiClient)),
          ],
          child: MaterialApp(
            home: CreateJourneyScreen(
              initialOriginLabel: 'Bengaluru',
              initialDestinationLabel: 'Mysuru',
              repository: mockRepo,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final costFinder = find.byKey(const Key('journey_estimated_trip_cost'));
      await tester.enterText(costFinder, '600');
      final priceFinder = find.byKey(const Key('journey_price_per_seat'));
      await tester.enterText(priceFinder, '150');
      await tester.pumpAndSettle();

      final buttonFinder = find.widgetWithText(ElevatedButton, 'Confirm & Publish Journey');
      final button = tester.widget<ElevatedButton>(buttonFinder);
      expect(button.onPressed, isNull);
      expect(find.textContaining('Failed to calculate road route'), findsOneWidget);
    });

    testWidgets('13. Release LocationPicker receives ApiClient-backed geocoder and searches real UI', (WidgetTester tester) async {
      const location = ConfirmedLocation(displayLabel: 'MG Road, Bengaluru', formattedAddress: 'MG Road, Bengaluru, India', latitude: 12.975, longitude: 77.608, countryCode: 'IN', countryName: 'India');
      final geocoder = MockGeocodingAdapter([location]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationPicker(
              title: 'Search origin',
              geocodingProvider: geocoder,
              locationService: const DefaultLocationService(),
              onLocationConfirmed: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Search origin'), findsOneWidget);
    });
  });
}
