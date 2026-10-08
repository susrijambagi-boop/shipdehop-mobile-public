import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/screens/parcelpool_screen.dart';
import 'package:shipdehop_mobile/widgets/trip_assistant_sheet.dart';
import 'package:shipdehop_mobile/widgets/ui/shd_location_header.dart';

void main() {
  setUp(() {
    Animate.defaultDuration = Duration.zero;
  });

  Future<void> disposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Future<void> closeDialog(WidgetTester tester, Finder finder) async {
    Navigator.of(tester.element(finder)).pop();
    await tester.pumpAndSettle();
  }

  group('iOS release UX hardening', () {
    test('Trip assistant extracts a multi-word route and date', () {
      final parsed = TripQuery.parse(
        "I'm travelling from Bangalore to Mangalore on 20 Sep",
      );
      expect(parsed.origin, 'Bangalore');
      expect(parsed.destination, 'Mangalore');
      expect(parsed.dateText, '20 Sep');
    });

    testWidgets('Home location header is prominent and actionable', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShdLocationHeader(
              locationName: 'Doha, Qatar',
              onTapLocation: () => tapped = true,
            ),
          ),
        ),
      );
      expect(find.text('EXPLORE FROM'), findsOneWidget);
      expect(find.text('Doha, Qatar'), findsOneWidget);
      expect(find.textContaining('Tap to change'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home_location_header')));
      expect(tapped, isTrue);
    });

    testWidgets('Parcel size can be changed', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ParcelPoolScreen(
              prefilledOrigin: 'Bengaluru, Karnataka',
              prefilledDestination: 'Mangaluru, Karnataka',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Selected: M · ≤5kg'), findsOneWidget);
      await tester.tap(find.byKey(const Key('parcel_size_L')));
      await tester.pumpAndSettle();
      expect(find.text('Selected: L · ≤10kg'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('Send Parcel date row opens a date picker', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ParcelPoolScreen())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send_date_row')));
      await tester.pumpAndSettle();
      final dialog = find.byType(DatePickerDialog);
      expect(dialog, findsOneWidget);
      await closeDialog(tester, dialog);
      await disposeScreen(tester);
    });

    testWidgets('Bring Item description row opens an editable sheet', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: ParcelPoolScreen(initialModeIndex: 1)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bring_item_row')));
      await tester.pumpAndSettle();
      final input = find.byKey(const Key('bring_item_input'));
      expect(find.text('What do you need?'), findsOneWidget);
      expect(input, findsOneWidget);
      await closeDialog(tester, input);
      await disposeScreen(tester);
    });

    testWidgets("I'm Travelling date row opens a date picker", (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: ParcelPoolScreen(initialModeIndex: 2)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('travel_date_row')));
      await tester.pumpAndSettle();
      final dialog = find.byType(DatePickerDialog);
      expect(dialog, findsOneWidget);
      await closeDialog(tester, dialog);
      await disposeScreen(tester);
    });
  });
}
