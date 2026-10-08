import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/screens/cargo_matches_screen.dart';
import 'package:shipdehop_mobile/screens/my_routes_screen.dart';
import 'package:shipdehop_mobile/screens/publish_route_screen.dart';

void main() {
  group('NumberFormatLite Unit Tests', () {
    test('Formats distances under 1000m as meters', () {
      expect(NumberFormatLite.meters(450), equals('450 m'));
      expect(NumberFormatLite.meters(0), equals('0 m'));
      expect(NumberFormatLite.meters(999), equals('999 m'));
    });

    test('Formats distances 1000m and above as kilometers', () {
      expect(NumberFormatLite.meters(1000), equals('1.0 km'));
      expect(NumberFormatLite.meters(2500), equals('2.5 km'));
      expect(NumberFormatLite.meters(15400), equals('15.4 km'));
    });
  });

  group('PublishRouteScreen Widget Tests', () {
    testWidgets('Renders route publishing form fields properly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PublishRouteScreen(),
          ),
        ),
      );

      expect(find.byType(PublishRouteScreen), findsOneWidget);
      expect(find.text('Publish Carrier Route'), findsOneWidget);
      expect(find.text('Journey Origin'), findsOneWidget);
      expect(find.text('Journey Destination'), findsOneWidget);
      expect(find.text('Carrier Departure Timing Window'), findsOneWidget);
    });
  });

  group('CargoMatchesScreen Widget Tests', () {
    testWidgets('Renders CargoMatchesScreen shell properly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CargoMatchesScreen(tripId: '00000000-0000-0000-0000-000000000000'),
          ),
        ),
      );

      expect(find.byType(CargoMatchesScreen), findsOneWidget);
      expect(find.text('Corridor Parcel Matches'), findsOneWidget);
      expect(find.text('Max Route Detour:'), findsOneWidget);
    });
  });

  group('MyRoutesScreen Widget Tests', () {
    testWidgets('Renders MyRoutesScreen shell and published route card properly', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myRoutesProvider.overrideWith((ref) async => [
                  {
                    'id': '11111111-1111-1111-1111-111111111111',
                    'origin_name': 'Mumbai',
                    'dest_name': 'Pune',
                    'departure_time': '2026-08-23T12:00:00.000Z',
                    'seat_capacity': 2,
                    'parcel_capacity_tier': 'MEDIUM',
                    'price_per_seat': 300,
                    'currency': 'INR',
                    'status': 'SCHEDULED',
                  }
                ]),
          ],
          child: const MaterialApp(
            home: MyRoutesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(MyRoutesScreen), findsOneWidget);
      expect(find.text('My Published Routes'), findsOneWidget);
      expect(find.text('Mumbai → Pune'), findsOneWidget);
    });
  });
}
