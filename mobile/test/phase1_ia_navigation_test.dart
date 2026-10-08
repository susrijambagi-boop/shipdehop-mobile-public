import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/api_client.dart';
import 'package:shipdehop_mobile/core/intent_router.dart';
import 'package:shipdehop_mobile/models/domain.dart';
import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/screens/main_home_screen.dart';
import 'package:shipdehop_mobile/widgets/global_header.dart';

class MockApiClient extends Fake implements ApiClient {
  @override
  Future<dynamic> get(String path, {bool requireAuth = true}) async => <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool requireAuth = true}) async => <String, dynamic>{};
}

void main() {
  group('Phase 1 IA & Intent Router Unit Tests', () {
    const router = DeterministicIntentRouter();

    test('Parses parcel send intent correctly', () {
      final res = router.parseQuery('Send a parcel from Mumbai to Pune');
      expect(res.type, IntentType.parcelSend);
      expect(res.targetTab, 1); // ParcelPool
      expect(res.targetModeIndex, 0); // Shipster
      expect(res.origin, 'Mumbai');
      expect(res.destination, 'Pune');
    });

    test('Parses buy for me shopster intent correctly', () {
      final res = router.parseQuery('Buy perfume from Dubai');
      expect(res.type, IntentType.parcelShop);
      expect(res.targetTab, 1); // ParcelPool
      expect(res.targetModeIndex, 1); // Shopster
      expect(res.itemDescription, 'perfume');
    });

    test('Parses driving / offer ride intent correctly', () {
      final res = router.parseQuery('Driving to Pune tomorrow');
      expect(res.type, IntentType.carpoolOffer);
      expect(res.targetTab, 2); // CarPool
      expect(res.targetModeIndex, 1); // Poolice
    });

    test('Parses ride seat intent correctly', () {
      final res = router.parseQuery('Need a ride to Bangalore');
      expect(res.type, IntentType.carpoolRide);
      expect(res.targetTab, 2); // CarPool
      expect(res.targetModeIndex, 0); // Pooler
    });

    test('Parses sell item intent correctly', () {
      final res = router.parseQuery('Sell my iPhone');
      expect(res.type, IntentType.marketplaceSell);
      expect(res.targetTab, 3); // Marketplace
      expect(res.targetModeIndex, 1); // Lister
    });
  });

  group('Phase 1 Navigation Shell Widget Tests', () {
    testWidgets('Renders 5 primary bottom navigation tabs', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockApiClient()),
            shipmentFeedProvider.overrideWith((ref) async => <ShipmentCardModel>[]),
            marketplaceFeedProvider.overrideWith((ref) async => <MarketplaceCardModel>[]),
            myRoutesProvider.overrideWith((ref) async => <Map<String, dynamic>>[]),
          ],
          child: const MaterialApp(
            home: MainHomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Explore'), findsWidgets);
      expect(find.text('ParcelPool'), findsWidgets);
      expect(find.text('CarPool'), findsWidgets);
      expect(find.text('Marketplace'), findsWidgets);
      expect(find.text('History'), findsWidgets);
      expect(find.byType(GlobalHeader), findsOneWidget);
    });

    testWidgets('Switching tabs changes view', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            apiClientProvider.overrideWithValue(MockApiClient()),
            shipmentFeedProvider.overrideWith((ref) async => <ShipmentCardModel>[]),
            marketplaceFeedProvider.overrideWith((ref) async => <MarketplaceCardModel>[]),
            myRoutesProvider.overrideWith((ref) async => <Map<String, dynamic>>[]),
          ],
          child: const MaterialApp(
            home: MainHomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap ParcelPool tab
      await tester.tap(find.widgetWithText(NavigationDestination, 'ParcelPool'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Send Parcel'), findsWidgets);

      // Tap CarPool tab
      await tester.tap(find.widgetWithText(NavigationDestination, 'CarPool'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Find a Ride'), findsWidgets);

      // Tap Marketplace tab
      await tester.tap(find.widgetWithText(NavigationDestination, 'Marketplace'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Browse Market'), findsWidgets);
    });
  });
}
