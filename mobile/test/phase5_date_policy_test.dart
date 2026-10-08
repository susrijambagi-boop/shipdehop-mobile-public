import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/policy_resolver.dart';
import 'package:shipdehop_mobile/models/confirmed_location.dart';
import 'package:shipdehop_mobile/models/date_flexibility.dart';
import 'package:shipdehop_mobile/widgets/date_flexibility_picker.dart';
import 'package:shipdehop_mobile/widgets/policy_summary_card.dart';

void main() {
  const mumbai = ConfirmedLocation(
    displayLabel: 'Mumbai, Maharashtra',
    formattedAddress: 'Mumbai, India',
    latitude: 19.0760,
    longitude: 72.8777,
    countryCode: 'IN',
    countryName: 'India',
  );

  const pune = ConfirmedLocation(
    displayLabel: 'Pune, Maharashtra',
    formattedAddress: 'Pune, India',
    latitude: 18.5204,
    longitude: 73.8567,
    countryCode: 'IN',
    countryName: 'India',
  );

  const doha = ConfirmedLocation(
    displayLabel: 'Doha, Qatar',
    formattedAddress: 'Doha, Qatar',
    latitude: 25.2854,
    longitude: 51.5310,
    countryCode: 'QA',
    countryName: 'Qatar',
  );

  const lusail = ConfirmedLocation(
    displayLabel: 'Lusail, Qatar',
    formattedAddress: 'Lusail City, Qatar',
    latitude: 25.4200,
    longitude: 51.4900,
    countryCode: 'QA',
    countryName: 'Qatar',
  );

  const dubai = ConfirmedLocation(
    displayLabel: 'Dubai, UAE',
    formattedAddress: 'Dubai, United Arab Emirates',
    latitude: 25.2048,
    longitude: 55.2708,
    countryCode: 'AE',
    countryName: 'United Arab Emirates',
  );

  group('Phase 5 DateFlexibility Model Unit Tests', () {
    test('DateFlexibility detects invalid reversed date range', () {
      final flex = DateFlexibility(
        earliestDateTime: DateTime.now().add(const Duration(hours: 10)),
        latestDateTime: DateTime.now().add(const Duration(hours: 2)),
        isFlexible: true,
      );

      expect(flex.isValid, isFalse);
      expect(flex.validationError, contains('cannot precede earliest'));
    });

    test('DateFlexibility formats flexible window label correctly', () {
      final flex = DateFlexibility(
        earliestDateTime: DateTime.utc(2026, 8, 24, 2, 30),
        latestDateTime: DateTime(2026, 8, 25, 20, 0),
        isFlexible: true,
        flexibilityWindowHours: 1,
      );

      expect(flex.formattedFlexibility, contains('24 Aug 2026, 08:00 IST'));
      expect(flex.formattedFlexibility, contains('±1 hr'));
    });
  });

  group('Phase 5 PolicyResolver Unit Tests', () {
    test('Mumbai -> Pune resolves to India, INR, IN as supported policy', () {
      PolicyResolver.setTestFixturePolicy('IN', const ResolvedPolicy(
        countryName: 'India',
        countryCode: 'IN',
        currency: 'INR',
        jurisdictionCode: 'IN',
        isSupported: true,
        isCrossBorder: false,
        maxRecoveryRatio: 1.25,
      ));
      final policy = PolicyResolver.resolvePolicy(mumbai, pune);

      expect(policy.countryName, 'India');
      expect(policy.currency, 'INR');
      expect(policy.jurisdictionCode, 'IN');
      expect(policy.isSupported, isTrue);
      expect(policy.maxRecoveryRatio, 1.25);
      PolicyResolver.clearTestFixturePolicies();
    });

    test('Doha -> Lusail resolves to unsupported policy for non-India location', () {
      final policy = PolicyResolver.resolvePolicy(doha, lusail);

      expect(policy.isSupported, isFalse);
      expect(policy.unsupportedReason, 'Currently available in India.');
    });

    test('Dubai -> Abu Dhabi resolves to unsupported policy for non-India location', () {
      final policy = PolicyResolver.resolvePolicy(dubai, doha);

      expect(policy.isSupported, isFalse);
      expect(policy.unsupportedReason, 'Currently available in India.');
    });

    test('India -> Qatar route is unsupported', () {
      final policy = PolicyResolver.resolvePolicy(mumbai, doha);

      expect(policy.isCrossBorder, isTrue);
      expect(policy.isSupported, isFalse);
      expect(policy.unsupportedReason, 'Currently available in India.');
    });
  });

  group('Phase 5 Widget Tests for DateFlexibilityPicker & PolicySummaryCard', () {
    testWidgets('PolicySummaryCard renders India supported policy summary', (tester) async {
      final policy = PolicyResolver.resolvePolicy(mumbai, pune);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PolicySummaryCard(policy: policy)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('India launch area'), findsOneWidget);
      expect(find.text('India • Currency: INR'), findsOneWidget);
      expect(find.text('INR'), findsOneWidget);
    });

    testWidgets('PolicySummaryCard renders non-India unsupported policy message cleanly', (tester) async {
      final policy = PolicyResolver.resolvePolicy(doha, lusail);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PolicySummaryCard(policy: policy),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Currently available in India.'), findsWidgets);
    });

    testWidgets('DateFlexibilityPicker allows toggling flexibility window', (tester) async {
      DateFlexibility? updatedFlex;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateFlexibilityPicker(
              title: 'Pickup & Delivery Timing Window',
              initialValue: DateFlexibility(
                earliestDateTime: DateTime.now().add(const Duration(hours: 2)),
                latestDateTime: DateTime.now().add(const Duration(hours: 24)),
                isFlexible: false,
              ),
              onChanged: (val) => updatedFlex = val,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pickup & Delivery Timing Window'), findsOneWidget);
      expect(find.text('Flexible'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(updatedFlex, isNotNull);
      expect(updatedFlex!.isFlexible, isTrue);
    });
  });
}

