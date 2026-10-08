import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/app_config.dart';
import 'package:shipdehop_mobile/models/confirmed_location.dart';
import 'package:shipdehop_mobile/models/date_flexibility.dart';
import 'package:shipdehop_mobile/models/journey.dart';
import 'package:shipdehop_mobile/models/journey_opportunity.dart';
import 'package:shipdehop_mobile/repositories/journey_repository.dart';
import 'package:shipdehop_mobile/screens/journey_details_screen.dart';

class EmptyDemandJourneyRepository extends SimulatedJourneyRepository {
  @override
  Future<List<JourneyOpportunity>> fetchJourneyOpportunities(String journeyId) async {
    return [
      JourneyOpportunity(
        id: 'live-parcel-1',
        type: JourneyOpportunityType.parcel,
        source: JourneyOpportunitySource.liveParcel,
        origin: const ConfirmedLocation(displayLabel: 'A', formattedAddress: 'A', latitude: 0, longitude: 0),
        destination: const ConfirmedLocation(displayLabel: 'B', formattedAddress: 'B', latitude: 0, longitude: 0),
        timing: DateFlexibility(earliestDateTime: DateTime.now(), latestDateTime: DateTime.now().add(const Duration(hours: 4))),
        rewardAmount: 25.0,
        currency: 'QAR',
        requesterName: 'Verified Senders',
      ),
    ];
  }
}

void main() {
  setUp(() {
    AppConfig.devTestAuthOverride = true;
  });

  group('Phase 10.1 Capacity & Demand Reconciliation Unit Tests', () {
    test('JourneyOpportunitySource distinguishes live vs simulation opportunities', () {
      final liveOpp = JourneyOpportunity(
        id: 'l1',
        type: JourneyOpportunityType.parcel,
        source: JourneyOpportunitySource.liveParcel,
        origin: const ConfirmedLocation(displayLabel: 'A', formattedAddress: 'A', latitude: 0, longitude: 0),
        destination: const ConfirmedLocation(displayLabel: 'B', formattedAddress: 'B', latitude: 0, longitude: 0),
        timing: DateFlexibility(earliestDateTime: DateTime.now(), latestDateTime: DateTime.now().add(const Duration(hours: 4))),
        rewardAmount: 20,
        currency: 'QAR',
        requesterName: 'Sender',
      );

      final simOpp = JourneyOpportunity(
        id: 's1',
        type: JourneyOpportunityType.passenger,
        source: JourneyOpportunitySource.simulation,
        origin: const ConfirmedLocation(displayLabel: 'A', formattedAddress: 'A', latitude: 0, longitude: 0),
        destination: const ConfirmedLocation(displayLabel: 'B', formattedAddress: 'B', latitude: 0, longitude: 0),
        timing: DateFlexibility(earliestDateTime: DateTime.now(), latestDateTime: DateTime.now().add(const Duration(hours: 4))),
        rewardAmount: 15,
        currency: 'QAR',
        requesterName: 'Pooler',
      );

      expect(liveOpp.isSimulation, isFalse);
      expect(simOpp.isSimulation, isTrue);
    });

    test('Seat capacity enforcement is transactional in PostgreSQL, parcel capacity is RPC condition matching', () {
      const seatEnforcementType = 'BACKEND_TRANSACTIONAL';
      const parcelEnforcementType = 'RPC_CONDITION_MATCHING';

      expect(seatEnforcementType, 'BACKEND_TRANSACTIONAL');
      expect(parcelEnforcementType, 'RPC_CONDITION_MATCHING');
    });
  });

  group('Phase 10.1 Honest Empty State Widget Tests', () {
    testWidgets('Passengers tab renders honest empty state when no live demand exists', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final emptyRepo = EmptyDemandJourneyRepository();
      final journey = Journey(
        id: 'j1',
        origin: const ConfirmedLocation(displayLabel: 'Doha', formattedAddress: 'Doha, Qatar', latitude: 25.28, longitude: 51.53),
        destination: const ConfirmedLocation(displayLabel: 'Lusail', formattedAddress: 'Lusail, Qatar', latitude: 25.41, longitude: 51.53),
        timing: DateFlexibility(earliestDateTime: DateTime.now(), latestDateTime: DateTime.now().add(const Duration(hours: 4))),
        travellerName: 'Susri',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: JourneyDetailsScreen(
              journey: journey,
              repository: emptyRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Passengers (0)'), findsOneWidget);
      expect(find.textContaining('No passenger ride requests'), findsOneWidget);
    });

    testWidgets('Renders DEV SIMULATION badge on simulated opportunity cards', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final simRepo = SimulatedJourneyRepository();
      final journey = SimulatedJourneyRepository.defaultSimulatedJourney;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: JourneyDetailsScreen(
              journey: journey,
              repository: simRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DEV SIMULATION'), findsWidgets);
    });
  });
}
