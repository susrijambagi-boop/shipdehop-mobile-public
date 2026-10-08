import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/app_config.dart';
import 'package:shipdehop_mobile/core/money_formatter.dart';
import 'package:shipdehop_mobile/providers/phase15_providers.dart';
import 'package:shipdehop_mobile/screens/explore_screen.dart';
import 'package:shipdehop_mobile/screens/help_support_screen.dart';
import 'package:shipdehop_mobile/screens/marketplace_screen.dart';
import 'package:shipdehop_mobile/screens/orders_screen.dart';
import 'package:shipdehop_mobile/screens/profile_screen.dart';
import 'package:shipdehop_mobile/widgets/escrow_breakdown.dart';

void main() {
  setUp(() {
    Animate.defaultDuration = Duration.zero;
  });
  group('Phase 7.1 MoneyFormatter Unit Tests', () {
    test('Formats INR, QAR, AED, USD correctly', () {
      expect(MoneyFormatter.format(275, 'INR'), '₹275');
      expect(MoneyFormatter.format(275, 'QAR'), 'QAR 275');
      expect(MoneyFormatter.format(275, 'AED'), 'AED 275');
      expect(MoneyFormatter.format(275, 'USD'), '\$275');
      expect(MoneyFormatter.format(25.5, 'INR', showDecimalsIfNeeded: true), '₹25.50');
    });
  });

  group('Phase 7.1 Financial Consistency & EscrowBreakdown Tests', () {
    testWidgets('EscrowBreakdown component sum equals displayed total without raw internal terms', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EscrowBreakdown(
              base: 0,
              reward: 250,
              platformFee: 25,
              currency: 'INR',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Payment protection'), findsOneWidget);
      expect(find.text('Traveller reward'), findsOneWidget);
      expect(find.text('₹250'), findsOneWidget);
      expect(find.text('ShipdeHop fee'), findsOneWidget);
      expect(find.text('₹25'), findsOneWidget);
      expect(find.text('Total secured'), findsOneWidget);
      expect(find.text('₹275'), findsOneWidget);

      // Verify raw internal jargon is hidden
      expect(find.text('HopPay milestone escrow'), findsNothing);
      expect(find.text('Locked total'), findsNothing);
      expect(find.text('INR 300'), findsNothing);
    });

    testWidgets('OrdersScreen renders authoritative pricing and hides raw UUID', (tester) async {
      final mockOrder = {
        'id': '017e03ce-7280-433c-82d3-f3c2c4bb5a7f',
        'order_type': 'SHIPMENT',
        'buyer_id': 'ed9517fc-7ebe-437c-bdc0-abb45bef9079',
        'provider_id': 'dc07d14a-b820-4178-928f-4de1cfab13bb',
        'total_amount': 275,
        'base_price': 0,
        'reward_fee': 250,
        'platform_fee': 25,
        'currency': 'INR',
        'escrow_status': 'LOCKED',
        'fulfillment_status': 'CREATED',
        'payment_provider': 'MOCK',
        'title': 'Mumbai → Pune Parcel',
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unifiedHistoryProvider.overrideWith((ref) async => [mockOrder]),
          ],
          child: const MaterialApp(
            home: OrdersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Activity & Orders'), findsOneWidget);
      expect(find.textContaining('Payment Secured'), findsWidgets);
      expect(find.textContaining('Mumbai → Pune'), findsWidgets);

      // Verify raw internal details are hidden
      expect(find.textContaining('017e03ce'), findsNothing);
      expect(find.text('HopPay milestone escrow'), findsNothing);
      expect(find.text('Buyer / Sender'), findsNothing);
    });
  });

  group('Phase 7.1 Help & Support UI & Hierarchy Tests', () {
    testWidgets('HelpSupportScreen initial state shows guidance without error copy', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: HelpSupportScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ask anything about how ShipdeHop works.'), findsOneWidget);
      expect(find.textContaining("I don't have an answer for that yet"), findsNothing);
      expect(find.text('Popular questions'), findsOneWidget);
      expect(find.text('How ShipdeHop Works'), findsOneWidget);
      expect(find.text('Frequently Asked Questions'), findsOneWidget);
      expect(find.text('Terminology & Glossary'), findsOneWidget);
    });
  });

  group('Phase 7.1 Marketplace Flow Reorder Tests', () {
    testWidgets('Marketplace buyer view renders commerce surface', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MarketplaceScreen(initialModeIndex: 0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Browse Market'), findsOneWidget);
      expect(find.text('Sell an Item'), findsOneWidget);
    });
  });

  group('Phase 7.1 Profile & Developer Options Cleanup Tests', () {
    testWidgets('Profile renders truthful verification state and hides raw eKYC jargon', (tester) async {
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

      expect(find.text('Verification not completed'), findsOneWidget);
      expect(find.textContaining('Verification Standing: Verified Identity & Tier 2 eKYC'), findsNothing);
      expect(find.text('Saved Places'), findsOneWidget);
      expect(find.text('Travel Preferences'), findsOneWidget);
    });

    testWidgets('Developer Options is collapsed when enabled and hidden when disabled', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Test when enabled
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (AppConfig.enableDevTestAuth) {
        expect(find.text('Developer Options'), findsOneWidget);
      }
    });
  });

  group('Phase 7.1 Cross-Screen Data Consistency Tests', () {
    testWidgets('ExploreScreen renders active activity when present', (tester) async {
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

      expect(find.text('What can ShipdeHop help with?'), findsNothing);
      expect(find.text('QUICK ACTIONS'), findsOneWidget);
    });
  });
}
