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

class ParcelCapacityJourneyRepository extends SimulatedJourneyRepository {
  @override
  Future<List<JourneyOpportunity>> fetchJourneyOpportunities(String journeyId) async {
    return [
      JourneyOpportunity(
        id: 'task-small-1',
        type: JourneyOpportunityType.parcel,
        source: JourneyOpportunitySource.liveParcel,
        origin: const ConfirmedLocation(displayLabel: 'Doha Corniche', formattedAddress: 'Doha, Qatar', latitude: 25.29, longitude: 51.53),
        destination: const ConfirmedLocation(displayLabel: 'Lusail Marina', formattedAddress: 'Lusail, Qatar', latitude: 25.41, longitude: 51.53),
        timing: DateFlexibility(earliestDateTime: DateTime.now(), latestDateTime: DateTime.now().add(const Duration(hours: 4))),
        rewardAmount: 35.0,
        currency: 'QAR',
        weightKg: 0.8,
        requiredParcelUnits: 1,
        requesterName: 'Small Item Shipper',
      ),
      JourneyOpportunity(
        id: 'task-large-2',
        type: JourneyOpportunityType.parcel,
        source: JourneyOpportunitySource.liveParcel,
        origin: const ConfirmedLocation(displayLabel: 'Doha West Bay', formattedAddress: 'Doha, Qatar', latitude: 25.32, longitude: 51.53),
        destination: const ConfirmedLocation(displayLabel: 'Lusail City', formattedAddress: 'Lusail, Qatar', latitude: 25.42, longitude: 51.53),
        timing: DateFlexibility(earliestDateTime: DateTime.now(), latestDateTime: DateTime.now().add(const Duration(hours: 4))),
        rewardAmount: 90.0,
        currency: 'QAR',
        weightKg: 8.5,
        requiredParcelUnits: 6,
        requesterName: 'Heavy Cargo Shipper',
      ),
    ];
  }
}

int calculateParcelCapacityFromWeight(double weightKg) {
  if (weightKg <= 1.0) return 1;
  if (weightKg <= 5.0) return 3;
  return 6;
}

void main() {
  setUp(() {
    AppConfig.devTestAuthOverride = true;
  });

  final defaultFlex = DateFlexibility(
    earliestDateTime: DateTime.now(),
    latestDateTime: DateTime.now().add(const Duration(hours: 4)),
  );

  group('Phase 12 Parcel Capacity Unit & Model Tests', () {
    test('Automatic weight-to-capacity calculation rules', () {
      // <= 1.0 kg => 1 unit
      expect(calculateParcelCapacityFromWeight(0.5), 1);
      expect(calculateParcelCapacityFromWeight(1.0), 1);

      // > 1.0 and <= 5.0 kg => 3 units
      expect(calculateParcelCapacityFromWeight(1.1), 3);
      expect(calculateParcelCapacityFromWeight(3.0), 3);
      expect(calculateParcelCapacityFromWeight(5.0), 3);

      // > 5.0 kg => 6 units
      expect(calculateParcelCapacityFromWeight(5.1), 6);
      expect(calculateParcelCapacityFromWeight(8.0), 6);
      expect(calculateParcelCapacityFromWeight(25.0), 6);
    });

    test('Updating weight recalculates parcel capacity units', () {
      double weight = 0.5;
      int units = calculateParcelCapacityFromWeight(weight);
      expect(units, 1);

      // Shipper updates parcel weight from 0.5kg to 3.5kg
      weight = 3.5;
      units = calculateParcelCapacityFromWeight(weight);
      expect(units, 3);

      // Shipper updates parcel weight from 3.5kg to 10kg
      weight = 10.0;
      units = calculateParcelCapacityFromWeight(weight);
      expect(units, 6);
    });

    test('Capacity constraint invariants', () {
      final journey = Journey(
        id: 'j-inv',
        origin: ConfirmedLocation(displayLabel: 'Doha', formattedAddress: 'Doha', latitude: 25.28, longitude: 51.53),
        destination: ConfirmedLocation(displayLabel: 'Lusail', formattedAddress: 'Lusail', latitude: 25.41, longitude: 51.53),
        timing: defaultFlex,
        travellerName: 'Verified Traveller',
        parcelCapacityTier: 'MEDIUM',
        parcelCapacityUnitsTotal: 6,
        parcelCapacityUnitsAvailable: 4,
      );

      expect(journey.parcelCapacityUnitsTotal >= 0, isTrue);
      expect(journey.parcelCapacityUnitsAvailable >= 0, isTrue);
      expect(journey.parcelCapacityUnitsAvailable <= journey.parcelCapacityUnitsTotal, isTrue);
    });

    test('Journey parcel capacity units initialize correctly from tier mapping', () {
      final envelopeJourney = Journey(
        id: 'j-env',
        origin: const ConfirmedLocation(displayLabel: 'Doha', formattedAddress: 'Doha', latitude: 25.28, longitude: 51.53),
        destination: const ConfirmedLocation(displayLabel: 'Lusail', formattedAddress: 'Lusail', latitude: 25.41, longitude: 51.53),
        timing: defaultFlex,
        travellerName: 'Carrier 1',
        parcelCapacityTier: 'ENVELOPE',
      );
      expect(envelopeJourney.parcelCapacityUnitsTotal, 2);
      expect(envelopeJourney.parcelCapacityUnitsAvailable, 2);

      final mediumJourney = Journey(
        id: 'j-med',
        origin: const ConfirmedLocation(displayLabel: 'Doha', formattedAddress: 'Doha', latitude: 25.28, longitude: 51.53),
        destination: const ConfirmedLocation(displayLabel: 'Lusail', formattedAddress: 'Lusail', latitude: 25.41, longitude: 51.53),
        timing: defaultFlex,
        travellerName: 'Carrier 2',
        parcelCapacityTier: 'MEDIUM',
      );
      expect(mediumJourney.parcelCapacityUnitsTotal, 6);
      expect(mediumJourney.parcelCapacityUnitsAvailable, 6);

      final luggageJourney = Journey(
        id: 'j-lug',
        origin: const ConfirmedLocation(displayLabel: 'Doha', formattedAddress: 'Doha', latitude: 25.28, longitude: 51.53),
        destination: const ConfirmedLocation(displayLabel: 'Lusail', formattedAddress: 'Lusail', latitude: 25.41, longitude: 51.53),
        timing: defaultFlex,
        travellerName: 'Carrier 3',
        parcelCapacityTier: 'LUGGAGE',
      );
      expect(luggageJourney.parcelCapacityUnitsTotal, 12);
      expect(luggageJourney.parcelCapacityUnitsAvailable, 12);
    });

    test('Journey Opportunity calculates fit label correctly based on available units', () {
      final oppSmall = JourneyOpportunity(
        id: 'o-1',
        type: JourneyOpportunityType.parcel,
        origin: const ConfirmedLocation(displayLabel: 'A', formattedAddress: 'A', latitude: 25.2, longitude: 51.5),
        destination: const ConfirmedLocation(displayLabel: 'B', formattedAddress: 'B', latitude: 25.4, longitude: 51.5),
        timing: defaultFlex,
        rewardAmount: 20,
        currency: 'QAR',
        weightKg: 0.5,
        requiredParcelUnits: 1,
        requesterName: 'Shipper',
      );

      final oppLarge = JourneyOpportunity(
        id: 'o-2',
        type: JourneyOpportunityType.parcel,
        origin: const ConfirmedLocation(displayLabel: 'A', formattedAddress: 'A', latitude: 25.2, longitude: 51.5),
        destination: const ConfirmedLocation(displayLabel: 'B', formattedAddress: 'B', latitude: 25.4, longitude: 51.5),
        timing: defaultFlex,
        rewardAmount: 80,
        currency: 'QAR',
        weightKg: 8.0,
        requiredParcelUnits: 6,
        requesterName: 'Heavy Shipper',
      );

      // Available = 6 units
      expect(oppSmall.getFitLabel(6), 'Fits easily');
      expect(oppLarge.getFitLabel(6), 'Fits');

      // Available = 2 units (limited space)
      expect(oppSmall.getFitLabel(2), 'Fits easily');
      expect(oppLarge.getFitLabel(2), 'Too large');
      expect(oppLarge.calculateFitStatus(2), ParcelFitStatus.tooLarge);
    });
  });

  group('Phase 12 Widget & UI Tests', () {
    testWidgets('CreateJourneyScreen displays understandable carrying capacity options', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CreateJourneyScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Medium bag'), findsOneWidget);
      expect(find.textContaining('Accept parcel crowdshipping'), findsOneWidget);
    });

    testWidgets('JourneyDetailsScreen renders parcel capacity summary and fit labels', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = ParcelCapacityJourneyRepository();
      final journey = Journey(
        id: 'j-cap-1',
        origin: const ConfirmedLocation(displayLabel: 'Doha', formattedAddress: 'Doha', latitude: 25.28, longitude: 51.53),
        destination: const ConfirmedLocation(displayLabel: 'Lusail', formattedAddress: 'Lusail', latitude: 25.41, longitude: 51.53),
        timing: defaultFlex,
        travellerName: 'Verified Traveller',
        parcelCapacityTier: 'MEDIUM',
        parcelCapacityUnitsTotal: 6,
        parcelCapacityUnitsAvailable: 2,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: JourneyDetailsScreen(
              journey: journey,
              repository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Medium capacity • 2 of 6 units available'), findsOneWidget);

      await tester.tap(find.text('Parcels (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Fits easily'), findsOneWidget);
      expect(find.text('Too large'), findsOneWidget);
    });
  });
}
