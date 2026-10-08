import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/api_client.dart';
import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/providers/phase15_providers.dart';
import 'package:shipdehop_mobile/screens/chat_inbox_screen.dart';
import 'package:shipdehop_mobile/screens/orders_screen.dart';
import 'package:shipdehop_mobile/screens/profile_screen.dart';
import 'package:shipdehop_mobile/widgets/breadcrumb_bar.dart';
import 'package:shipdehop_mobile/providers/notification_provider.dart';
import 'package:shipdehop_mobile/screens/notifications_sheet.dart';

class MockPhase2ApiClient implements ApiClient {
  @override
  Future<dynamic> get(String path, {bool requireAuth = true}) async {
    if (path == '/profile/me') {
      return {
        'id': 'phase2-user',
        'email': 'phase2@example.com',
        'fullName': 'Phase 2 User',
        'ekycTier': 'TIER_2',
        'isIdentityVerified': true,
        'identityVerificationStatus': 'VERIFIED',
        'trustScore': 70,
        'xpPoints': 350,
        'completedTransactionsCount': 1,
      };
    }
    if (path == '/history') {
      return [
        {
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
        }
      ];
    }
    return [];
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool requireAuth = true}) async => {};

  @override
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body, {bool requireAuth = true}) async => {};
}

void main() {
  setUp(() {
    Animate.defaultDuration = Duration.zero;
  });

  group('Phase 2 Unified History Widget Tests', () {
    testWidgets('Renders human-readable status for LOCKED order', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unifiedHistoryProvider.overrideWith((ref) async => [
                  {
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
                  }
                ]),
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
    });

    testWidgets('Renders History Category and Status filter chips', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockPhase2ApiClient()),
            userOrdersProvider.overrideWith((ref) async => <Map<String, dynamic>>[]),
          ],
          child: const MaterialApp(
            home: OrdersScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Parcels'), findsOneWidget);
      expect(find.text('Rides'), findsOneWidget);
      expect(find.text('Marketplace'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });
  });

  group('Phase 2 Messages Inbox & Notification Empty State Tests', () {
    testWidgets('Renders empty state for Messages when no threads exist', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            chatThreadsProvider.overrideWith((ref) async => <Map<String, dynamic>>[]),
          ],
          child: const MaterialApp(
            home: ChatInboxScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets('NotificationsSheet renders empty state when no active locked orders exist', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userOrdersProvider.overrideWith((ref) async => <Map<String, dynamic>>[]),
            notificationsProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(
            home: NotificationsSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No new notifications'), findsOneWidget);
      expect(find.text("We'll let you know about matches, payments, messages and safety updates here."), findsOneWidget);
    });
  });

  group('Phase 2 Universal Profile & Gamification Tests', () {
    testWidgets('Profile cleanly separates Trust Score from Gamification XP & Badges', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockPhase2ApiClient()),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ShipdeHop Verified'), findsOneWidget);
      expect(find.text('Trust Score'), findsOneWidget);
      expect(find.text('70 / 100'), findsOneWidget);
      expect(find.text('XP Points'), findsOneWidget);
    });
  });

  group('Phase 2 BreadcrumbBar Tests', () {
    testWidgets('BreadcrumbBar displays crumbs correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BreadcrumbBar(crumbs: ['Explore', 'ParcelPool', 'Shipster']),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('ParcelPool'), findsOneWidget);
      expect(find.text('Shipster'), findsOneWidget);
    });
  });
}
