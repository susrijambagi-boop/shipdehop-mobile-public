import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shipdehop_mobile/core/help_content.dart';
import 'package:shipdehop_mobile/screens/explore_screen.dart';
import 'package:shipdehop_mobile/screens/help_support_screen.dart';
import 'package:shipdehop_mobile/screens/hopship_screen.dart';
import 'package:shipdehop_mobile/screens/orders_screen.dart';
import 'package:shipdehop_mobile/screens/profile_screen.dart';
import 'package:shipdehop_mobile/widgets/contextual_help_button.dart';

void main() {
  setUp(() {
    Animate.defaultDuration = Duration.zero;
  });

  group('Phase 7 HelpContent & Glossary Unit Tests', () {
    test('Centralized HelpContent dictionary contains required terms', () {
      final shipster = HelpContent.findById('shipster');
      final hopster = HelpContent.findById('hopster');
      final shopster = HelpContent.findById('shopster');
      final pooler = HelpContent.findById('pooler');
      final poolice = HelpContent.findById('poolice');

      expect(shipster, isNotNull);
      expect(shipster!.title, 'Shipster');
      expect(hopster, isNotNull);
      expect(shopster, isNotNull);
      expect(pooler, isNotNull);
      expect(poolice, isNotNull);
    });

    test('HelpContent search handles query matching and unknown fallback', () {
      final matches = HelpContent.search('hopster');
      expect(matches, isNotEmpty);
      expect(matches.any((t) => t.id == 'hopster'), isTrue);

      final emptyMatches = HelpContent.search('xyz_nonmatching_query_string');
      expect(emptyMatches, isEmpty);
    });
  });

  group('Phase 7 Ask ShipdeHop AI Assistant & Help UI Tests', () {
    testWidgets('HelpSupportScreen renders Ask ShipdeHop and handles unknown queries honestly', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: HelpSupportScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ask ShipdeHop'), findsOneWidget);
      expect(find.text('Terminology & Glossary'), findsOneWidget);

      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'xyz_nonmatching_query_string');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text("I don't have an answer for that yet. Try one of the topics below."), findsOneWidget);
    });

    testWidgets('ContextualHelpButton opens modal with topic details', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextualHelpButton(
              topicId: 'shipster',
              style: ContextualHelpStyle.textLink,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final link = find.text('What does this mean?');
      expect(link, findsOneWidget);
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.text('Shipster'), findsWidgets);
      expect(find.textContaining('A sender using ParcelPool'), findsOneWidget);
    });
  });

  group('Phase 7 Consumer Terminology & Clean Copy Tests', () {
    testWidgets('ExploreScreen contains no old floating buttons or MOCK provider text', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ExploreScreen(onSelectTab: (_, {destination, int? modeIndex, origin}) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Routes'), findsNothing);
      expect(find.text('HopShip'), findsNothing);
      expect(find.text('Publish route'), findsNothing);
      expect(find.textContaining('Provider: MOCK'), findsNothing);
      expect(find.text('Opportunities along your journeys', skipOffstage: false), findsOneWidget);
    });

    testWidgets('HopShipScreen title is Send a Parcel (NOT Create New Parcel Task)', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HopShipScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Send a Parcel'), findsOneWidget);
      expect(find.text('Create HopShip Request'), findsNothing);
      expect(find.text('Create New Parcel Task'), findsNothing);
    });

    testWidgets('OrdersScreen title is My Activity & Orders (NOT Unified History)', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OrdersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Activity & Orders'), findsOneWidget);
      expect(find.text('Unified History'), findsNothing);
    });

    testWidgets('ProfileScreen removes progress framework and Admin tags', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trust Score'), findsOneWidget);
      expect(find.text('XP Points'), findsOneWidget);
      expect(find.textContaining('progress framework'), findsNothing);
      expect(find.textContaining('(Admin)'), findsNothing);
      expect(find.textContaining('Help &'), findsOneWidget);
    });
  });
}
