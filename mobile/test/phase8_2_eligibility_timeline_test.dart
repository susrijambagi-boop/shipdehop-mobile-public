import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/app_config.dart';
import 'package:shipdehop_mobile/core/delivery_lifecycle.dart';
import 'package:shipdehop_mobile/repositories/delivery_repository.dart';
import 'package:shipdehop_mobile/screens/delivery_details_screen.dart';
import 'package:shipdehop_mobile/widgets/delivery_progress_timeline.dart';

void main() {
  setUp(() {
    AppConfig.devTestAuthOverride = true;
  });

  group('Phase 8.2 DeliveryLifecycleActionHelper Action Eligibility Unit Tests', () {
    test('Sender at paymentSecured does NOT see View Handoff Code', () {
      const context = DeliveryLifecycleContext(
        orderId: 'test-1',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'CREATED',
        role: ConsumerUserRole.sender,
      );
      expect(DeliveryLifecycleActionHelper.canViewHandoffCode(context), isFalse);
    });

    test('Sender at readyForHandoff DOES see View Handoff Code', () {
      const context = DeliveryLifecycleContext(
        orderId: 'test-2',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'AWAITING_HANDOFF',
        role: ConsumerUserRole.sender,
      );
      expect(DeliveryLifecycleActionHelper.canViewHandoffCode(context), isTrue);
    });

    test('Sender at completed does NOT see active handoff action', () {
      const context = DeliveryLifecycleContext(
        orderId: 'test-3',
        escrowStatus: 'RELEASED',
        fulfillmentStatus: 'VERIFIED',
        role: ConsumerUserRole.sender,
      );
      expect(DeliveryLifecycleActionHelper.canViewHandoffCode(context), isFalse);
    });

    test('Traveller at paymentSecured sees Start Delivery but NOT Verify Handoff', () {
      const context = DeliveryLifecycleContext(
        orderId: 'test-4',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'CREATED',
        role: ConsumerUserRole.carrier,
      );
      expect(DeliveryLifecycleActionHelper.canStartDelivery(context), isTrue);
      expect(DeliveryLifecycleActionHelper.canVerifyHandoff(context), isFalse);
    });

    test('Traveller at inTransit sees Verify Handoff but NOT Start Delivery', () {
      const context = DeliveryLifecycleContext(
        orderId: 'test-5',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'IN_TRANSIT',
        role: ConsumerUserRole.carrier,
      );
      expect(DeliveryLifecycleActionHelper.canStartDelivery(context), isFalse);
      expect(DeliveryLifecycleActionHelper.canVerifyHandoff(context), isTrue);
    });
  });

  group('Phase 8.2 Timeline Semantics & Copy Unit Tests', () {
    testWidgets('Timeline renders Awaiting pickup and Payment is protected copy', (tester) async {
      const contextModel = DeliveryLifecycleContext(
        orderId: 'test-6',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'CREATED',
        role: ConsumerUserRole.sender,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeliveryProgressTimeline(contextModel: contextModel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Payment is protected until handoff'), findsOneWidget);
      expect(find.text('Awaiting pickup'), findsOneWidget);
      expect(find.text('Waiting for traveller to collect package'), findsOneWidget);
      expect(find.text('Pickup completed'), findsNothing);
    });

    testWidgets('IN_TRANSIT state marks Pickup completed on timeline', (tester) async {
      const contextModel = DeliveryLifecycleContext(
        orderId: 'test-7',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'IN_TRANSIT',
        eventTypes: ['CREATED', 'IN_TRANSIT'],
        role: ConsumerUserRole.sender,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeliveryProgressTimeline(contextModel: contextModel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pickup completed'), findsOneWidget);
      expect(find.text('Package collected by traveller'), findsOneWidget);
    });
  });

  group('Phase 8.2 DeliveryDetailsScreen Live Sender UI Verification', () {
    testWidgets('Sender at paymentSecured renders Awaiting pickup and NO handoff code button', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repository = SimulatedDeliveryRepository();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DeliveryDetailsScreen(
              orderId: 'fixture-secured',
              repository: repository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delivery Details'), findsOneWidget);
      expect(find.textContaining('Mumbai → Pune'), findsWidgets);
      expect(find.text('Awaiting pickup'), findsWidgets);
      expect(find.textContaining('Message'), findsWidgets);

      // Verify View Handoff Code is ABSENT at paymentSecured stage
      expect(find.text('View Handoff OTP / QR Code'), findsNothing);
    });

    testWidgets('Sender at readyForHandoff DOES render View Handoff Code button', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repository = SimulatedDeliveryRepository();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DeliveryDetailsScreen(
              orderId: 'fixture-handoff',
              repository: repository,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('View Handoff OTP / QR Code'), findsOneWidget);
    });
  });
}
