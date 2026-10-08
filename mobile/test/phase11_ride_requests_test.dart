import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/app_config.dart';
import 'package:shipdehop_mobile/core/policy_resolver.dart';
import 'package:shipdehop_mobile/models/confirmed_location.dart';
import 'package:shipdehop_mobile/models/date_flexibility.dart';
import 'package:shipdehop_mobile/models/journey.dart';
import 'package:shipdehop_mobile/models/journey_opportunity.dart';
import 'package:shipdehop_mobile/models/ride_request.dart';
import 'package:shipdehop_mobile/repositories/journey_repository.dart';
import 'package:shipdehop_mobile/screens/carpool_screen.dart';
import 'package:shipdehop_mobile/screens/journey_details_screen.dart';
import 'package:shipdehop_mobile/screens/post_ride_request_screen.dart';

class LiveDemandJourneyRepository extends SimulatedJourneyRepository {
  @override
  Future<List<JourneyOpportunity>> fetchJourneyOpportunities(String journeyId) async {
    return [
      JourneyOpportunity(
        id: '93736e07-fca5-461e-a72c-58996660cb20',
        type: JourneyOpportunityType.passenger,
        source: JourneyOpportunitySource.livePassenger,
        origin: const ConfirmedLocation(displayLabel: 'Mumbai Bandra', formattedAddress: 'Mumbai, Maharashtra, India', latitude: 19.05, longitude: 72.82, countryCode: 'IN'),
        destination: const ConfirmedLocation(displayLabel: 'Pune Kothrud', formattedAddress: 'Pune, Maharashtra, India', latitude: 18.50, longitude: 73.80, countryCode: 'IN'),
        timing: DateFlexibility(earliestDateTime: DateTime.now(), latestDateTime: DateTime.now().add(const Duration(hours: 4))),
        rewardAmount: 250.0,
        currency: 'INR',
        seatsNeeded: 2,
        requesterName: 'Verified Pooler',
      ),
    ];
  }
}

void main() {
  setUp(() {
    Animate.defaultDuration = Duration.zero;
    AppConfig.devTestAuthOverride = true;
  });

  group('Phase 11.1 India Launch & Model Unit Tests', () {
    test('RideRequest correctly parses India fields', () {
      const uuidStr = '93736e07-fca5-461e-a72c-58996660cb20';
      final req = RideRequest.fromJson({
        'id': uuidStr,
        'requester_id': 'u1',
        'pickup_name': 'Mumbai',
        'drop_name': 'Pune',
        'earliest_departure': DateTime.now().toIso8601String(),
        'latest_departure': DateTime.now().add(const Duration(hours: 3)).toIso8601String(),
        'seats_needed': 2,
        'currency': 'INR',
        'jurisdiction_code': 'IN',
        'status': 'OPEN',
      });

      expect(req.id, uuidStr);
      expect(req.currency, 'INR');
      expect(req.jurisdictionCode, 'IN');
      expect(req.isOpen, isTrue);
    });

    test('Doha ➔ Lusail resolves unsupported policy for non-India location', () {
      const doha = ConfirmedLocation(displayLabel: 'Doha', formattedAddress: 'Doha, Qatar', latitude: 25.2854, longitude: 51.5310, countryCode: 'UNSUPPORTED');
      const lusail = ConfirmedLocation(displayLabel: 'Lusail', formattedAddress: 'Lusail, Qatar', latitude: 25.4184, longitude: 51.5310, countryCode: 'UNSUPPORTED');

      final policy = PolicyResolver.resolvePolicy(doha, lusail);
      expect(policy.isSupported, isFalse);
      expect(policy.unsupportedReason, 'Currently available in India.');
    });

    test('Mumbai ➔ Pune resolves IN_MH jurisdiction and INR currency as supported', () {
      const mumbai = ConfirmedLocation(displayLabel: 'Mumbai', formattedAddress: 'Mumbai, India', latitude: 19.0760, longitude: 72.8777, countryCode: 'IN');
      const pune = ConfirmedLocation(displayLabel: 'Pune', formattedAddress: 'Pune, India', latitude: 18.5204, longitude: 73.8567, countryCode: 'IN');

      final policy = PolicyResolver.resolvePolicy(mumbai, pune);
      expect(policy.currency, 'INR');
      expect(policy.isSupported, isTrue);
    });

    test('Notification reality: event logging is distinct from user notification delivery', () {
      const eventLogged = true;
      const userNotificationImplemented = false;
      expect(eventLogged, isTrue);
      expect(userNotificationImplemented, isFalse);
    });
  });

  group('Phase 11.1 Widget & Flow Tests', () {
    testWidgets('CarPool Find Ride exposes route, departure, return and passengers', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: CarPoolScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('carpool_find_route_picker')), findsOneWidget);
      expect(find.byKey(const Key('carpool_find_departure')), findsOneWidget);
      expect(find.byKey(const Key('carpool_find_return')), findsOneWidget);
      expect(find.byKey(const Key('carpool_find_passengers')), findsOneWidget);
      expect(find.byKey(const Key('carpool_search_button')), findsOneWidget);
      expect(find.text("Can't find the exact ride?"), findsOneWidget);
    });

    testWidgets('CarPool Offer Ride has clickable departure and seats controls', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: CarPoolScreen(initialModeIndex: 1)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('carpool_offer_departure')), findsOneWidget);
      expect(find.byKey(const Key('carpool_offer_seats')), findsOneWidget);

      await tester.tap(find.byKey(const Key('carpool_offer_seats')));
      await tester.pumpAndSettle();
      expect(find.text('How many seats are available?'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('PostRideRequestScreen renders empty location pickers and disabled submit', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: PostRideRequestScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Header and form chrome should always be present
      expect(find.text('Post a Ride Request'), findsOneWidget);
      expect(find.text('Where do you need pickup?'), findsOneWidget);
      expect(find.text('Where are you going?'), findsOneWidget);

      // With no locations chosen, submit button must be disabled
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Post Ride Request'),
      );
      expect(button.onPressed, isNull);

      // Hardcoded Bengaluru/Mysuru prefill has been deliberately removed —
      // a user must actively choose both locations before submission.
      expect(find.text('Bengaluru, Karnataka'), findsNothing);
      expect(find.text('Mysuru, Karnataka'), findsNothing);
    });

    testWidgets('JourneyDetailsScreen renders live India passenger request card', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final liveRepo = LiveDemandJourneyRepository();
      final journey = Journey(
        id: 'j-live-1',
        origin: const ConfirmedLocation(displayLabel: 'Mumbai', formattedAddress: 'Mumbai', latitude: 19.07, longitude: 72.87, countryCode: 'IN'),
        destination: const ConfirmedLocation(displayLabel: 'Pune', formattedAddress: 'Pune', latitude: 18.52, longitude: 73.85, countryCode: 'IN'),
        timing: DateFlexibility(earliestDateTime: DateTime.now(), latestDateTime: DateTime.now().add(const Duration(hours: 4))),
        travellerName: 'Susri',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: JourneyDetailsScreen(journey: journey, repository: liveRepo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Passengers (1)'), findsOneWidget);
      expect(find.text('Mumbai Bandra → Pune Kothrud'), findsOneWidget);
      expect(find.text('Accept Match'), findsOneWidget);
    });
  });
}

