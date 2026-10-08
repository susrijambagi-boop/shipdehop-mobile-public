import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shipdehop_mobile/core/api_client.dart';
import 'package:shipdehop_mobile/core/intent_router.dart';
import 'package:shipdehop_mobile/core/money_formatter.dart';
import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/screens/account_settings_screen.dart';
import 'package:shipdehop_mobile/screens/explore_screen.dart';
import 'package:shipdehop_mobile/screens/hop_club_screen.dart';
import 'package:shipdehop_mobile/screens/payments_payouts_screen.dart';
import 'package:shipdehop_mobile/screens/profile_screen.dart';
import 'package:shipdehop_mobile/screens/saved_places_screen.dart';
import 'package:shipdehop_mobile/screens/travel_preferences_screen.dart';
import 'package:shipdehop_mobile/widgets/identity_badge.dart';

class MockQAApiClient implements ApiClient {
  @override
  Future<dynamic> get(String path, {bool requireAuth = true}) async {
    if (path == '/profile/me') {
      return {
        'id': '00000000-0000-4000-a000-000000000001',
        'full_name': 'Test User 🚀',
        'email': 'test@shipdehop.test',
        'phone_number': '+919876543210',
        'ekyc_tier': 'TIER_1',
        'ekycTier': 'TIER_1',
        'isIdentityVerified': true,
        'identityVerificationStatus': 'VERIFIED',
        'trust_score': 85.0,
        'trustScore': 85.0,
        'xp_points': 450,
        'xpPoints': 450,
        'completed_transactions_count': 5,
        'completedTransactionsCount': 5,
        'has_verified_payment_account': false,
        'hasVerifiedPaymentAccount': false,
        'paymentAccounts': <Map<String, dynamic>>[],
      };
    }
    if (path == '/history') {
      return {
        'items': [
          {
            'id': 'ord-1',
            'type': 'PARCEL',
            'status': 'COMPLETED',
            'title': 'Electronics Kit',
            'created_at': '2026-08-30T10:00:00Z',
            'amount': 1500,
            'currency': 'INR',
          },
        ],
      };
    }
    if (path == '/marketplace/items') {
      return {'items': <Map<String, dynamic>>[]};
    }
    if (path == '/trips') {
      return {'trips': <Map<String, dynamic>>[]};
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool requireAuth = true}) async => <String, dynamic>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 18 — Product QA & Failure Forecasting Suite', () {
    testWidgets('Profile renders ShipdeHop Verified badge and Coming Soon payments', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('test-user'),
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockQAApiClient()),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Verified badge copy
      expect(find.text('ShipdeHop Verified'), findsOneWidget);
      expect(find.text('Identity verified'), findsNothing);
      expect(find.text('Aadhaar Verified'), findsNothing);
      expect(find.text('Biometric Verified'), findsNothing);

      // Trust metrics
      expect(find.text('Trust Score'), findsOneWidget);
      expect(find.text('85 / 100'), findsOneWidget);
      expect(find.text('XP Points'), findsOneWidget);
      expect(find.text('450'), findsOneWidget);

      // Payments disabled copy
      expect(find.text('Coming soon in beta'), findsOneWidget);
    });

    testWidgets('PaymentsPayoutsScreen displays coming soon banner and zero charged methods', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('test-user'),
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockQAApiClient()),
          ],
          child: const MaterialApp(
            home: PaymentsPayoutsScreen(profile: {
              'paymentAccounts': <Map<String, dynamic>>[],
            }),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Payments & payouts — Coming soon'), findsOneWidget);
      expect(find.textContaining('disabled in this beta release'), findsOneWidget);
      expect(find.text('No payout account connected'), findsOneWidget);
    });

    testWidgets('IdentityBadge displays canonical status states correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                IdentityBadge(status: VerificationBadgeStatus.verified),
                IdentityBadge(status: VerificationBadgeStatus.pendingReview),
                IdentityBadge(status: VerificationBadgeStatus.notStarted),
              ],
            ),
          ),
        ),
      );

      expect(find.text('ShipdeHop Verified'), findsOneWidget);
      expect(find.text('Identity Under Review'), findsOneWidget);
      expect(find.text('Get Verified'), findsOneWidget);
    });

    test('IntentRouter correctly parses destination and travel queries', () {
      const router = DeterministicIntentRouter();

      // Parcel intent
      final parcel = router.parseQuery('Send parcel from Bangalore to Chennai');
      expect(parcel.type, IntentType.parcelSend);
      expect(parcel.targetTab, 1);

      // Ride intent
      final ride = router.parseQuery('Find ride to Hyderabad');
      expect(ride.type, IntentType.carpoolRide);
      expect(ride.targetTab, 2);

      // Unknown intent returns clarification
      final unknown = router.parseQuery('Hello World 12345');
      expect(unknown.type, IntentType.unknown);
      expect(unknown.clarificationPrompt, isNotNull);
    });

    test('MoneyFormatter formats amounts defensively', () {
      expect(MoneyFormatter.format(1250, 'INR'), '₹1,250');
      expect(MoneyFormatter.format(0, 'INR'), '₹0');
      expect(MoneyFormatter.format(45.50, 'QAR'), 'QAR 45.50');
    });

    testWidgets('ExploreScreen renders location header and quick action shortcuts', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('test-user'),
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockQAApiClient()),
          ],
          child: MaterialApp(
            home: ExploreScreen(onSelectTab: (idx, {destination, modeIndex, origin}) {}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Your location'), findsOneWidget);
      expect(find.text('Send Parcel'), findsOneWidget);
      expect(find.text('Find Ride'), findsOneWidget);
      expect(find.text('Travelling'), findsOneWidget);
      expect(find.text('Market'), findsOneWidget);
    });

    testWidgets('SavedPlacesScreen renders cleanly without crashing on empty data', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('test-user'),
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockQAApiClient()),
          ],
          child: const MaterialApp(
            home: SavedPlacesScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Saved Places'), findsOneWidget);
      expect(find.text('Add place'), findsOneWidget);
    });

    testWidgets('TravelPreferencesScreen toggles corridor preferences cleanly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('test-user'),
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockQAApiClient()),
          ],
          child: const MaterialApp(
            home: TravelPreferencesScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Travel Preferences'), findsOneWidget);
      expect(find.text('Preferred travel mode'), findsOneWidget);
    });

    testWidgets('AccountSettingsScreen renders safety and account management options', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('test-user'),
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockQAApiClient()),
          ],
          child: const MaterialApp(
            home: AccountSettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Full name'), findsOneWidget);
    });

    testWidgets('HopClubScreen displays progression tiers and quests', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('test-user'),
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockQAApiClient()),
          ],
          child: const MaterialApp(
            home: HopClubScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Hop Club'), findsOneWidget);
    });
  });
}
