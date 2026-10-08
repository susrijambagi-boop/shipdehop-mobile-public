import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/app_config.dart';
import 'package:shipdehop_mobile/core/delivery_lifecycle.dart';
import 'package:shipdehop_mobile/repositories/delivery_repository.dart';
import 'package:shipdehop_mobile/screens/delivery_details_screen.dart';
import 'package:shipdehop_mobile/screens/lifecycle_simulator_screen.dart';

void main() {
  setUp(() {
    AppConfig.devTestAuthOverride = true;
  });

  group('Phase 9.1 Reconciliation Unit & Contract Tests', () {
    test('PENDING escrow status resolves to reserved state, not inTransit or paymentSecured', () {
      const context = DeliveryLifecycleContext(
        orderId: 'test-pending',
        escrowStatus: 'PENDING',
        fulfillmentStatus: 'CREATED',
      );
      final state = DeliveryLifecycleMapper.resolveState(context);
      expect(state, DeliveryLifecycleState.reserved);
      expect(DeliveryLifecycleActionHelper.canStartDelivery(context), isFalse);
    });

    test('LOCKED escrow status is required before Start Delivery (canStartDelivery)', () {
      const lockedContext = DeliveryLifecycleContext(
        orderId: 'test-locked',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'CREATED',
        role: ConsumerUserRole.carrier,
      );
      expect(DeliveryLifecycleActionHelper.canStartDelivery(lockedContext), isTrue);

      const pendingContext = DeliveryLifecycleContext(
        orderId: 'test-pending-carrier',
        escrowStatus: 'PENDING',
        fulfillmentStatus: 'CREATED',
        role: ConsumerUserRole.carrier,
      );
      expect(DeliveryLifecycleActionHelper.canStartDelivery(pendingContext), isFalse);
    });

    test('IN_TRANSIT state permits handoff code viewing for Sender per backend contract', () {
      const inTransitSender = DeliveryLifecycleContext(
        orderId: 'test-intransit-sender',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'IN_TRANSIT',
        role: ConsumerUserRole.sender,
      );
      expect(DeliveryLifecycleActionHelper.canViewHandoffCode(inTransitSender), isTrue);
    });

    test('IN_TRANSIT state permits handoff verification for Carrier per backend contract', () {
      const inTransitCarrier = DeliveryLifecycleContext(
        orderId: 'test-intransit-carrier',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'IN_TRANSIT',
        role: ConsumerUserRole.carrier,
      );
      expect(DeliveryLifecycleActionHelper.canVerifyHandoff(inTransitCarrier), isTrue);
    });

    test('AWAITING_HANDOFF remains supported in DeliveryLifecycleMapper if encountered', () {
      const awaitingHandoffContext = DeliveryLifecycleContext(
        orderId: 'test-awaiting',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'AWAITING_HANDOFF',
        role: ConsumerUserRole.sender,
      );
      final state = DeliveryLifecycleMapper.resolveState(awaitingHandoffContext);
      expect(state, DeliveryLifecycleState.readyForHandoff);
      expect(DeliveryLifecycleActionHelper.canViewHandoffCode(awaitingHandoffContext), isTrue);
    });
  });

  group('Phase 9.1 UI Reconciliation Widget Tests', () {
    testWidgets('Sender at IN_TRANSIT / readyForHandoff stage sees View Handoff OTP / QR Code button on DeliveryDetailsScreen', (tester) async {
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

      expect(find.text('Delivery Details'), findsOneWidget);
      expect(find.text('Ready for Handoff'), findsWidgets);
      expect(find.text('View Handoff OTP / QR Code'), findsOneWidget);
    });

    testWidgets('LifecycleSimulatorScreen renders synthetic note on ready for handoff state', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LifecycleSimulatorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3. Ready for Handoff (Synthetic)'), findsOneWidget);
    });
  });
}
