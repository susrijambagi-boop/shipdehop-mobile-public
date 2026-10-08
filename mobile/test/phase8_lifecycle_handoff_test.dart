import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/delivery_error_translator.dart';
import 'package:shipdehop_mobile/core/delivery_lifecycle.dart';
import 'package:shipdehop_mobile/core/help_content.dart';
import 'package:shipdehop_mobile/repositories/delivery_repository.dart';
import 'package:shipdehop_mobile/screens/delivery_details_screen.dart';
import 'package:shipdehop_mobile/widgets/delivery_progress_timeline.dart';
import 'package:shipdehop_mobile/widgets/sender_handoff_modal.dart';
import 'package:shipdehop_mobile/widgets/traveller_handoff_modal.dart';

void main() {
  group('Phase 8 Central DeliveryLifecycleMapper Unit Tests', () {
    test('LOCKED + CREATED resolves to paymentSecured (Awaiting pickup)', () {
      const context = DeliveryLifecycleContext(
        orderId: 'test-1',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'CREATED',
      );
      final state = DeliveryLifecycleMapper.resolveState(context);
      expect(state, DeliveryLifecycleState.paymentSecured);
      expect(DeliveryLifecycleMapper.getTitle(state), 'Payment Secured');
      expect(DeliveryLifecycleMapper.getSubtitle(state), 'Awaiting pickup');
    });

    test('LOCKED + IN_TRANSIT resolves to inTransit', () {
      const context = DeliveryLifecycleContext(
        orderId: 'test-2',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'IN_TRANSIT',
        eventTypes: ['CREATED', 'IN_TRANSIT'],
      );
      final state = DeliveryLifecycleMapper.resolveState(context);
      expect(state, DeliveryLifecycleState.inTransit);
      expect(DeliveryLifecycleMapper.getTitle(state), 'In Transit');
    });

    test('RELEASED + VERIFIED resolves to completed with milestone evidence', () {
      const context = DeliveryLifecycleContext(
        orderId: 'test-3',
        escrowStatus: 'RELEASED',
        fulfillmentStatus: 'VERIFIED',
        eventTypes: ['CREATED', 'PAYMENT_LOCKED', 'IN_TRANSIT', 'HANDOFF_VERIFIED'],
      );
      final state = DeliveryLifecycleMapper.resolveState(context);
      expect(state, DeliveryLifecycleState.completed);
      expect(DeliveryLifecycleMapper.getTitle(state), 'Completed');
      expect(context.hasEventHandoffVerified, isTrue);
    });

    test('PENDING expired resolves to cancelled', () {
      final past = DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();
      final context = DeliveryLifecycleContext(
        orderId: 'test-4',
        escrowStatus: 'PENDING',
        fulfillmentStatus: 'CREATED',
        reservationExpiresAt: past,
      );
      final state = DeliveryLifecycleMapper.resolveState(context);
      expect(state, DeliveryLifecycleState.cancelled);
    });
  });

  group('Phase 8 Error Translator & Security Tests', () {
    test('DeliveryErrorTranslator converts raw backend errors to clean consumer copy', () {
      expect(
        DeliveryErrorTranslator.translate('Invalid OTP'),
        "That verification code isn't correct. Please check with the sender.",
      );
      expect(
        DeliveryErrorTranslator.translate('OTP expired'),
        "This code has expired. Ask the sender to refresh their handoff code.",
      );
      expect(
        DeliveryErrorTranslator.translate('OTP verification temporarily locked'),
        "Too many failed attempts. Verification is locked for 15 minutes.",
      );
      expect(
        DeliveryErrorTranslator.translate('Invalid QR token'),
        "This isn't a valid ShipdeHop handoff code for this order.",
      );
    });

    test('Sensitive OTP/QR values are omitted from translated error strings', () {
      final err = DeliveryException('Invalid OTP 849201 secret_token_abc');
      expect(err.toString(), contains("isn't correct"));
      expect(err.toString(), isNot(contains('849201')));
      expect(err.toString(), isNot(contains('secret_token_abc')));
    });
  });

  group('Phase 8 Repository & Safety Guard Tests', () {
    test('SimulatedDeliveryRepository runs offline without network calls', () async {
      final repo = SimulatedDeliveryRepository();
      final data = await repo.fetchDeliveryDetails('fixture-secured', 'sender-1');
      expect(data.order['id'], 'fixture-secured');
      expect(data.lifecycleContext.escrowStatus, 'LOCKED');
    });

    test('Development Safety Guard blocks mutations on protected order 017e03ce...', () async {
      final repo = SafetyGuardedTestRepository();

      const protectedId = '017e03ce-7280-433c-82d3-f3c2c4bb5a7f';

      expect(
        () => repo.markInTransit(protectedId),
        throwsA(isA<DeliveryException>()),
      );
      expect(
        () => repo.fetchHandoffSecret(protectedId),
        throwsA(isA<DeliveryException>()),
      );
      expect(
        () => repo.verifyHandoffOtp(protectedId, '123456'),
        throwsA(isA<DeliveryException>()),
      );
    });
  });

  group('Phase 8 HelpContent Lifecycle Additions Tests', () {
    test('HelpContent dictionary contains all Phase 8 lifecycle topics', () {
      final topics = [
        'pickup',
        'in_transit',
        'handoff_verification',
        'otp_handoff',
        'qr_handoff',
        'payment_release',
        'delivery_completion',
        'live_location',
      ];
      for (final id in topics) {
        final topic = HelpContent.findById(id);
        expect(topic, isNotNull, reason: 'Missing topic $id');
      }
    });
  });

  group('Phase 8 UI & Widget Tests', () {
    testWidgets('DeliveryProgressTimeline renders milestone steps correctly', (tester) async {
      const contextModel = DeliveryLifecycleContext(
        orderId: 'fixture-intransit',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'IN_TRANSIT',
        eventTypes: ['CREATED', 'PAYMENT_LOCKED', 'IN_TRANSIT'],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeliveryProgressTimeline(contextModel: contextModel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delivery Progress'), findsOneWidget);
      expect(find.text('Request matched'), findsOneWidget);
      expect(find.text('Payment secured'), findsOneWidget);
      expect(find.text('In transit'), findsWidgets);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('DeliveryDetailsScreen renders canonical sections for simulated order', (tester) async {
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
      expect(find.textContaining('Mumbai'), findsWidgets);
      expect(find.text('Payment Secured'), findsWidgets);
      expect(find.text('Awaiting pickup'), findsWidgets);
      expect(find.text('View Handoff OTP / QR Code'), findsNothing);
      expect(find.text('Route & Pickup Locations'), findsOneWidget);
      expect(find.text('Live Location Tracking'), findsOneWidget);
      expect(find.text('Payment Summary'), findsOneWidget);
      expect(find.text('₹275'), findsWidgets);
    });

    testWidgets('Sender at paymentSecured does not see handoff code', (tester) async {
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

      expect(find.text('View Handoff OTP / QR Code'), findsNothing);
    });

    testWidgets('SenderHandoffModal renders OTP code and QR canvas', (tester) async {
      final repository = SimulatedDeliveryRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => SenderHandoffModal.show(ctx, 'fixture-secured', repository),
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Handoff Verification'), findsOneWidget);
      expect(find.text('849201'), findsOneWidget);
      expect(find.text('6-Digit OTP Code'), findsOneWidget);
    });

    testWidgets('TravellerHandoffModal validates 6-digit OTP input', (tester) async {
      final repository = SimulatedDeliveryRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => TravellerHandoffModal.show(ctx, 'fixture-intransit', repository, () {}),
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Verify Delivery Handoff'), findsOneWidget);
      expect(find.text('Option A: Enter OTP'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '12');
      await tester.tap(find.text('Verify OTP & Release Payment'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a 6-digit verification code.'), findsOneWidget);
    });
  });
}

class SafetyGuardedTestRepository implements DeliveryRepository {
  static const String protectedOrderId = '017e03ce-7280-433c-82d3-f3c2c4bb5a7f';

  void _guard(String orderId) {
    if (orderId.toLowerCase() == protectedOrderId.toLowerCase()) {
      throw DeliveryException('Protected test order is read-only in development mode.');
    }
  }

  @override
  Future<DeliveryDetailsData> fetchDeliveryDetails(String orderId, String? currentUserId) async {
    return DeliveryDetailsData(
      order: {'id': orderId},
      lifecycleContext: const DeliveryLifecycleContext(),
      events: const [],
    );
  }

  @override
  Future<void> lockEscrow(String orderId) async => _guard(orderId);

  @override
  Future<void> markInTransit(String orderId) async => _guard(orderId);

  @override
  Future<HandoffSecretData> fetchPickupSecret(String orderId) async {
    _guard(orderId);
    return const HandoffSecretData(otp: '', qrPayload: '', expiresInSeconds: 1800);
  }

  @override
  Future<void> confirmPickup(String orderId, {String? pickupCode, String? qrToken}) async => _guard(orderId);

  @override
  Future<HandoffSecretData> fetchHandoffSecret(String orderId) async {
    _guard(orderId);
    return const HandoffSecretData(otp: '', qrPayload: '', expiresInSeconds: 1800);
  }

  @override
  Future<void> verifyHandoffOtp(String orderId, String otp) async => _guard(orderId);

  @override
  Future<void> verifyHandoffQr(String orderId, String qrPayload) async => _guard(orderId);

  @override
  Future<void> acceptMatch(String orderId) async => _guard(orderId);

  @override
  Future<void> cancelOrder(String orderId, {String? reason}) async => _guard(orderId);

  @override
  Future<void> reportIssue(String orderId, String category, String description) async => _guard(orderId);
}
