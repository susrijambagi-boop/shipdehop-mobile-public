import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/app_config.dart';
import 'package:shipdehop_mobile/models/confirmed_location.dart';
import 'package:shipdehop_mobile/models/date_flexibility.dart';
import 'package:shipdehop_mobile/models/journey.dart';
import 'package:shipdehop_mobile/models/journey_opportunity.dart';
import 'package:shipdehop_mobile/repositories/journey_repository.dart';
import 'package:shipdehop_mobile/screens/create_journey_screen.dart';
import 'package:shipdehop_mobile/screens/journey_details_screen.dart';

void main() {
  setUp(() {
    AppConfig.devTestAuthOverride = true;
  });

  group('Phase 10 Unified Journey Unit & Model Tests', () {
    test('Journey model supports passengers, parcels, and shopping flags simultaneously', () {
      final now = DateTime.now();
      final journey = Journey(
        id: 'journey-test-1',
        origin: const ConfirmedLocation(displayLabel: 'Mumbai', formattedAddress: 'Mumbai, Maharashtra, India', latitude: 19.0760, longitude: 72.8777, countryCode: 'IN'),
        destination: const ConfirmedLocation(displayLabel: 'Pune', formattedAddress: 'Pune, Maharashtra, India', latitude: 18.5204, longitude: 73.8567, countryCode: 'IN'),
        timing: DateFlexibility(earliestDateTime: now, latestDateTime: now.add(const Duration(hours: 4))),
        travellerName: 'Susri',
        seatCapacity: 3,
        availableSeats: 2,
        acceptsParcels: true,
        parcelCapacityTier: 'MEDIUM',
        acceptsShoppingRequests: true,
      );

      expect(journey.acceptsPassengers, isTrue);
      expect(journey.acceptsParcels, isTrue);
      expect(journey.acceptsShoppingRequests, isTrue);
      expect(journey.statusLabel, 'Open for matches');
    });

    test('JourneyOpportunity normalization and score calculation', () {
      final now = DateTime.now();
      final greatOpp = JourneyOpportunity(
        id: 'o1',
        type: JourneyOpportunityType.parcel,
        origin: const ConfirmedLocation(displayLabel: 'A', formattedAddress: 'A', latitude: 0, longitude: 0),
        destination: const ConfirmedLocation(displayLabel: 'B', formattedAddress: 'B', latitude: 0, longitude: 0),
        timing: DateFlexibility(earliestDateTime: now, latestDateTime: now.add(const Duration(hours: 4))),
        rewardAmount: 350,
        currency: 'INR',
        requesterName: 'Aisha',
        pickupDistanceMeters: 500,
        dropDistanceMeters: 800,
        matchScore: JourneyOpportunity.calculateScore(500, 800),
      );
      expect(greatOpp.typeLabel, 'Parcel Delivery');
      expect(greatOpp.scoreLabel, 'Great match');

      final goodOpp = JourneyOpportunity(
        id: 'o2',
        type: JourneyOpportunityType.passenger,
        origin: const ConfirmedLocation(displayLabel: 'A', formattedAddress: 'A', latitude: 0, longitude: 0),
        destination: const ConfirmedLocation(displayLabel: 'B', formattedAddress: 'B', latitude: 0, longitude: 0),
        timing: DateFlexibility(earliestDateTime: now, latestDateTime: now.add(const Duration(hours: 4))),
        rewardAmount: 250,
        currency: 'INR',
        seatsNeeded: 1,
        requesterName: 'Tariq',
        pickupDistanceMeters: 3000,
        dropDistanceMeters: 4500,
        matchScore: JourneyOpportunity.calculateScore(3000, 4500),
      );
      expect(goodOpp.typeLabel, 'Passenger Ride');
      expect(goodOpp.scoreLabel, 'Good match');
    });

    test('SimulatedJourneyRepository returns Mumbai -> Pune journey with 3 normalized opportunities', () async {
      final repo = SimulatedJourneyRepository();
      final journey = await repo.fetchJourneyDetails('journey-mumbai-pune');
      expect(journey.origin.displayLabel, 'Mumbai');
      expect(journey.destination.displayLabel, 'Pune');

      final opps = await repo.fetchJourneyOpportunities('journey-mumbai-pune');
      expect(opps.length, 3);
      expect(opps.any((o) => o.type == JourneyOpportunityType.passenger), isTrue);
      expect(opps.any((o) => o.type == JourneyOpportunityType.parcel), isTrue);
      expect(opps.any((o) => o.type == JourneyOpportunityType.shoppingRequest), isTrue);
    });
  });

  group('Phase 10 Unified Journey Widget Tests', () {
    testWidgets('CreateJourneyScreen renders 3-step unified creation choices', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: CreateJourneyScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create a Journey'), findsOneWidget);
      expect(find.text('What capabilities do you offer on this trip?'), findsOneWidget);
      expect(find.textContaining('Accept passenger ride matches'), findsOneWidget);
      expect(find.textContaining('Accept parcel crowdshipping'), findsOneWidget);
      expect(find.textContaining('Accept Buy-for-Me requests'), findsOneWidget);
      expect(find.text('Confirm & Publish Journey'), findsOneWidget);
    });

    testWidgets('JourneyDetailsScreen groups opportunities into Passengers, Parcels, and Shopping tabs', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = SimulatedJourneyRepository();
      final journey = SimulatedJourneyRepository.defaultSimulatedJourney;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: JourneyDetailsScreen(journey: journey, repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Journey Details'), findsOneWidget);
      expect(find.text('Mumbai → Pune'), findsOneWidget);
      expect(find.text('Capacity Summary'), findsOneWidget);
      expect(find.text('Opportunities Along Your Journey'), findsOneWidget);
      expect(find.textContaining('Passengers (1)'), findsOneWidget);
      expect(find.textContaining('Parcels (1)'), findsOneWidget);
      expect(find.textContaining('Shopping (1)'), findsOneWidget);
    });
  });
}
