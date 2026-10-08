import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shipdehop_mobile/core/delivery_lifecycle.dart';
import 'package:shipdehop_mobile/repositories/delivery_repository.dart';
import 'package:shipdehop_mobile/screens/delivery_details_screen.dart';
import 'package:shipdehop_mobile/screens/hopship_screen.dart';

class MockBeta1DeliveryRepository implements DeliveryRepository {
  final Map<String, DeliveryDetailsData> _store = {};
  bool acceptMatchCalled = false;
  bool cancelOrderCalled = false;
  bool reportIssueCalled = false;
  bool markInTransitCalled = false;
  String? reportedCategory;

  void seedOrder(String orderId, DeliveryDetailsData data) {
    _store[orderId] = data;
  }

  @override
  Future<DeliveryDetailsData> fetchDeliveryDetails(String orderId, String? currentUserId) async {
    return _store[orderId]!;
  }

  @override
  Future<void> lockEscrow(String orderId) async {
    acceptMatchCalled = true;
  }

  @override
  Future<void> acceptMatch(String orderId) async {
    acceptMatchCalled = true;
  }

  @override
  Future<void> markInTransit(String orderId) async {
    markInTransitCalled = true;
  }

  @override
  Future<HandoffSecretData> fetchPickupSecret(String orderId) async {
    return const HandoffSecretData(
      otp: '654321',
      qrPayload: 'shipdehop://pickup/test-order?token=test_pickup_token',
      expiresInSeconds: 1800,
    );
  }

  @override
  Future<void> confirmPickup(String orderId, {String? pickupCode, String? qrToken}) async {
    markInTransitCalled = true;
  }

  @override
  Future<HandoffSecretData> fetchHandoffSecret(String orderId) async {
    return const HandoffSecretData(
      otp: '123456',
      qrPayload: 'shipdehop://handoff/test-order?token=test_token',
      expiresInSeconds: 1800,
    );
  }

  @override
  Future<void> verifyHandoffOtp(String orderId, String otp) async {}

  @override
  Future<void> verifyHandoffQr(String orderId, String qrPayload) async {}

  @override
  Future<void> cancelOrder(String orderId, {String? reason}) async {
    cancelOrderCalled = true;
  }

  @override
  Future<void> reportIssue(String orderId, String category, String description) async {
    reportIssueCalled = true;
    reportedCategory = category;
  }
}

void main() {
  group('Phase 20: Beta 1 Marketplace Loop Mobile UI Tests', () {
    testWidgets('HopShipScreen displays prohibited items checkbox and requires acknowledgement', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: HopShipScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Checkbox exists with concise prohibited categories
      expect(find.textContaining('I confirm this parcel does not contain prohibited or dangerous items'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);

      // Submit button is present
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('DeliveryDetailsScreen shows truthful Beta 1 copy and Accept Match CTA for sender', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = MockBeta1DeliveryRepository();
      const testOrderId = 'ord-123';
      repo.seedOrder(
        testOrderId,
        DeliveryDetailsData(
          order: {
            'id': testOrderId,
            'order_type': 'SHIPMENT',
            'buyer_id': 'sender-1',
            'provider_id': 'traveller-1',
            'fulfillment_status': 'CREATED',
            'escrow_status': 'PENDING',
            'total_amount': 0,
            'base_price': 0,
            'reward_fee': 0,
            'platform_fee': 0,
            'currency': 'INR',
          },
          lifecycleContext: const DeliveryLifecycleContext(
            orderId: testOrderId,
            fulfillmentStatus: 'CREATED',
            escrowStatus: 'PENDING',
            role: ConsumerUserRole.sender,
          ),
          events: const [],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DeliveryDetailsScreen(
              orderId: testOrderId,
              repository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Truthful Beta banner rendered
      expect(find.text('Beta Delivery · Payments Disabled'), findsOneWidget);
      expect(find.textContaining('No money, escrow, or platform fees are processed'), findsOneWidget);

      // Truthful Lifecycle Title
      expect(find.text('Match Awaiting Acceptance'), findsAtLeastNWidgets(1));

      // Sender CTA is Accept match without payment
      expect(find.text('Accept traveller match (No payment in beta)'), findsOneWidget);

      // Tap Accept match
      await tester.tap(find.text('Accept traveller match (No payment in beta)'));
      await tester.pumpAndSettle();
      expect(repo.acceptMatchCalled, true);
    });

    testWidgets('DeliveryDetailsScreen shows Start Delivery CTA for carrier when match is accepted', (tester) async {
      final repo = MockBeta1DeliveryRepository();
      const testOrderId = 'ord-456';
      repo.seedOrder(
        testOrderId,
        DeliveryDetailsData(
          order: {
            'id': testOrderId,
            'order_type': 'SHIPMENT',
            'buyer_id': 'sender-1',
            'provider_id': 'traveller-1',
            'fulfillment_status': 'READY',
            'escrow_status': 'LOCKED', // In UI mapper, LOCKED + READY maps to paymentSecured
            'total_amount': 150,
            'base_price': 0,
            'reward_fee': 150,
            'platform_fee': 0,
            'currency': 'INR',
          },
          lifecycleContext: const DeliveryLifecycleContext(
            orderId: testOrderId,
            fulfillmentStatus: 'READY',
            escrowStatus: 'LOCKED',
            role: ConsumerUserRole.carrier,
          ),
          events: const [],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DeliveryDetailsScreen(
              orderId: testOrderId,
              repository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Carrier action is Start Delivery with pickup code
      expect(find.text('Enter pickup code · start delivery'), findsOneWidget);
    });

    testWidgets('DeliveryDetailsScreen shows Report an Issue dialog and calls repository', (tester) async {
      final repo = MockBeta1DeliveryRepository();
      const testOrderId = 'ord-789';
      repo.seedOrder(
        testOrderId,
        DeliveryDetailsData(
          order: {
            'id': testOrderId,
            'order_type': 'SHIPMENT',
            'buyer_id': 'sender-1',
            'provider_id': 'traveller-1',
            'fulfillment_status': 'READY',
            'escrow_status': 'LOCKED',
            'total_amount': 150,
            'base_price': 0,
            'reward_fee': 150,
            'platform_fee': 0,
            'currency': 'INR',
          },
          lifecycleContext: const DeliveryLifecycleContext(
            orderId: testOrderId,
            fulfillmentStatus: 'READY',
            escrowStatus: 'LOCKED',
            role: ConsumerUserRole.sender,
          ),
          events: const [],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DeliveryDetailsScreen(
              orderId: testOrderId,
              repository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Report an issue
      expect(find.text('Report an issue'), findsOneWidget);
      await tester.tap(find.text('Report an issue'));
      await tester.pumpAndSettle();

      // Dialog is displayed
      expect(find.text('Select category:'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Enter description and submit
      await tester.enterText(find.byType(TextField), 'Sender was not available at pickup location');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit Report'));
      await tester.pumpAndSettle();

      expect(repo.reportIssueCalled, true);
    });
  });
}
