import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/providers/hopship_provider.dart';
import 'package:shipdehop_mobile/screens/hopship_screen.dart';

void main() {
  group('HopShieldResult Model Tests', () {
    test('HopShieldResult.fromJson parses APPROVED result correctly', () {
      final json = {
        'decision': 'APPROVED',
        'confidence': 0.98,
        'contentMismatch': false,
        'prohibitedCategories': <String>[],
        'rationale': 'Ordinary consumer electronic device.',
      };

      final result = HopShieldResult.fromJson(json);
      expect(result.decision, equals('APPROVED'));
      expect(result.confidence, equals(0.98));
      expect(result.contentMismatch, isFalse);
      expect(result.prohibitedCategories, isEmpty);
      expect(result.rationale, contains('Ordinary consumer'));
    });

    test('HopShieldResult.fromJson parses BLOCKED result with categories', () {
      final json = {
        'decision': 'BLOCKED',
        'confidence': 0.99,
        'contentMismatch': true,
        'prohibitedCategories': ['weapon', 'hazardous'],
        'rationale': 'Dangerous item detected.',
      };

      final result = HopShieldResult.fromJson(json);
      expect(result.decision, equals('BLOCKED'));
      expect(result.contentMismatch, isTrue);
      expect(result.prohibitedCategories, contains('weapon'));
    });
  });

  group('HopShipScreen Widget Tests', () {
    testWidgets('Renders HopShip sender form fields properly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HopShipScreen(),
          ),
        ),
      );

      expect(find.byType(HopShipScreen), findsOneWidget);
      expect(find.text('Send a Parcel'), findsOneWidget);
      expect(find.textContaining('Send'), findsWidgets);
      expect(find.textContaining('Request an item'), findsOneWidget);
      expect(find.text('Pickup Location'), findsOneWidget);
      expect(find.text('Drop-off Location'), findsOneWidget);
    });
  });
}
