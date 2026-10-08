import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/intent_router.dart';
import 'package:shipdehop_mobile/models/confirmed_location.dart';
import 'package:shipdehop_mobile/models/date_flexibility.dart';
import 'package:shipdehop_mobile/models/gamification_framework.dart';
import 'package:shipdehop_mobile/models/journey.dart';
import 'package:shipdehop_mobile/screens/explore_screen.dart';

void main() {
  setUp(() {
    Animate.defaultDuration = Duration.zero;
  });

  const origin = ConfirmedLocation(
    displayLabel: 'Mumbai, Maharashtra',
    formattedAddress: 'Mumbai, India',
    latitude: 19.0760,
    longitude: 72.8777,
    countryCode: 'IN',
  );

  const destination = ConfirmedLocation(
    displayLabel: 'Pune, Maharashtra',
    formattedAddress: 'Pune, India',
    latitude: 18.5204,
    longitude: 73.8567,
    countryCode: 'IN',
  );

  group('Phase 6 Shared Journey Model Unit Tests', () {
    test('Journey presentation model formats title and opportunity summary', () {
      final journey = Journey(
        id: 'j_123',
        origin: origin,
        destination: destination,
        timing: DateFlexibility(
          earliestDateTime: DateTime.now(),
          latestDateTime: DateTime.now().add(const Duration(hours: 12)),
        ),
        travellerName: 'Susri',
        opportunities: const JourneyOpportunitySummary(
          parcelRequestsCount: 2,
          poolerRequestsCount: 1,
          shopsterRequestsCount: 0,
        ),
      );
      expect(journey.displayTitle, 'Mumbai, Maharashtra → Pune, Maharashtra');
      expect(journey.opportunities.formattedSummary, '2 Parcels • 1 Pooler');
      expect(journey.opportunities.totalOpportunities, 3);
    });

    test('JourneyOpportunitySummary handles zero opportunities honestly', () {
      const summary = JourneyOpportunitySummary(
        parcelRequestsCount: 0,
        poolerRequestsCount: 0,
        shopsterRequestsCount: 0,
      );
      expect(summary.formattedSummary, 'No active opportunities along corridor');
      expect(summary.totalOpportunities, 0);
    });
  });

  group('Phase 6 GamificationFramework Unit Tests', () {
    test('Derives UserLevel and badges strictly from real activity', () {
      final framework = GamificationFramework.deriveFromRealData(
        isEkycVerified: true,
        completedJourneysCount: 2,
        completedParcelsCount: 1,
        completedHandoffsCount: 0,
      );
      expect(framework.xp, 350);
      expect(framework.currentLevel, UserLevel.explorer);
      expect(framework.levelTitle, 'Explorer');
      final roadRegular =
          framework.badges.firstWhere((b) => b.id == 'road_regular');
      expect(roadRegular.isUnlocked, isFalse);
      expect(roadRegular.criteria, 'Complete 10 journeys');
      final earlyHopper =
          framework.badges.firstWhere((b) => b.id == 'early_hopper');
      expect(earlyHopper.isUnlocked, isTrue);
    });
  });

  group('Phase 6 Intent Router & Trip Assistant UI Tests', () {
    test('DeterministicIntentRouter still returns clarificationPrompt on unknown query', () {
      const router = DeterministicIntentRouter();
      final result = router.parseQuery('xyz random gibberish query');
      expect(result.type, IntentType.unknown);
      expect(
        result.clarificationPrompt,
        contains('Are you looking to send a parcel'),
      );
    });

    testWidgets(
        'ExploreScreen opens Trip Assistant and recommends combined CarPool + ParcelPool',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExploreScreen(
                onSelectTab: (_, {destination, int? modeIndex, origin}) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byKey(const Key('home_assistant_input'));
      await tester.enterText(
        searchField,
        "I'm travelling from Bangalore to Mangalore on 20 Sep",
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(find.text('ShipdeHop Trip Assistant'), findsOneWidget);
      expect(find.text('1. Confirm your trip'), findsOneWidget);
      expect(find.text('2. How are you travelling?'), findsOneWidget);
      expect(find.text('Bangalore'), findsOneWidget);
      expect(find.text('Mangalore'), findsOneWidget);

      final car = find.byKey(const Key('trip_mode_car'));
      expect(car, findsOneWidget);
      await tester.tap(car);
      await tester.pumpAndSettle();

      final assistantList = find.byType(ListView).last;
      expect(assistantList, findsOneWidget);

      final peopleQuestion = find.text('3. How many people are travelling?');
      for (var i = 0; i < 5 && peopleQuestion.evaluate().isEmpty; i++) {
        await tester.drag(assistantList, const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      expect(peopleQuestion, findsOneWidget);

      final recommendation = find.text('Combine ParcelPool + CarPool');
      for (var i = 0; i < 6 && recommendation.evaluate().isEmpty; i++) {
        await tester.drag(assistantList, const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      expect(recommendation, findsOneWidget);
      expect(
        find.byKey(const Key('trip_assistant_parcelpool_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('trip_assistant_carpool_button')),
        findsOneWidget,
      );
    });
  });
}
