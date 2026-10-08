import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shipdehop_mobile/core/app_config.dart';
import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/providers/phase15_providers.dart';
import 'package:shipdehop_mobile/repositories/delivery_repository.dart';
import 'package:shipdehop_mobile/screens/delivery_details_screen.dart';
import 'package:shipdehop_mobile/screens/explore_screen.dart';
import 'package:shipdehop_mobile/screens/lifecycle_simulator_screen.dart';
import 'package:shipdehop_mobile/screens/orders_screen.dart';
import 'package:shipdehop_mobile/screens/profile_screen.dart';
import 'package:flutter_animate/flutter_animate.dart';

void main() {
  setUp(() {
    Animate.defaultDuration = Duration.zero;
    AppConfig.devTestAuthOverride = true;
  });

  group('Phase 8.1 History & Explore Card Navigation Tests', () {
    testWidgets('History order card tap opens DeliveryDetailsScreen', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockOrder = {
        'id': '017e03ce-7280-433c-82d3-f3c2c4bb5a7f',
        'order_type': 'SHIPMENT',
        'buyer_id': 'sender-1',
        'provider_id': 'carrier-1',
        'total_amount': 275,
        'base_price': 0,
        'reward_fee': 250,
        'platform_fee': 25,
        'currency': 'INR',
        'escrow_status': 'LOCKED',
        'fulfillment_status': 'CREATED',
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
      expect(find.textContaining('Mumbai → Pune'), findsWidgets);

      // Tap card
      await tester.tap(find.textContaining('Mumbai → Pune').first);
      await tester.pumpAndSettle();

      expect(find.byType(DeliveryDetailsScreen), findsOneWidget);
      expect(find.text('Delivery Details'), findsOneWidget);
    });

    testWidgets('Explore View Details opens DeliveryDetailsScreen', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockOrder = {
        'id': '017e03ce-7280-433c-82d3-f3c2c4bb5a7f',
        'order_type': 'SHIPMENT',
        'buyer_id': 'sender-1',
        'provider_id': 'carrier-1',
        'total_amount': 275,
        'base_price': 0,
        'reward_fee': 250,
        'platform_fee': 25,
        'currency': 'INR',
        'escrow_status': 'LOCKED',
        'fulfillment_status': 'CREATED',
        'title': 'Mumbai → Pune Parcel',
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => Stream.value(null)),
            unifiedHistoryProvider.overrideWith((ref) async => [mockOrder]),
          ],
          child: MaterialApp(
            home: ExploreScreen(onSelectTab: (_, {destination, modeIndex, origin}) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Track'), findsOneWidget);
      await tester.tap(find.text('Track'));
      await tester.pumpAndSettle();

      expect(find.byType(DeliveryDetailsScreen), findsOneWidget);
    });
  });

  group('Phase 8.1 Dev Lifecycle Simulator Tests', () {
    testWidgets('Dev Simulator button visible in ProfileScreen under Developer Options when enableDevTestAuth is true', (tester) async {
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

      expect(find.text('Developer Options'), findsOneWidget);
      await tester.tap(find.text('Developer Options'));
      await tester.pumpAndSettle();

      expect(find.text('Delivery Lifecycle Simulator'), findsOneWidget);
    });

    testWidgets('LifecycleSimulatorScreen renders state and role controls offline', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LifecycleSimulatorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dev Lifecycle Simulator'), findsOneWidget);
      expect(find.text('Sender / Buyer'), findsOneWidget);
      expect(find.text('Traveller / Carrier'), findsOneWidget);
      expect(find.text('1. Payment Secured'), findsOneWidget);
      expect(find.text('2. In Transit'), findsOneWidget);
      expect(find.text('3. Ready for Handoff (Synthetic)'), findsOneWidget);
      expect(find.text('4. Completed'), findsOneWidget);
    });

    testWidgets('Switching role from Sender to Traveller changes allowed actions in simulator', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LifecycleSimulatorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select Ready for Handoff for Sender
      await tester.tap(find.widgetWithText(ChoiceChip, '3. Ready for Handoff (Synthetic)'));
      await tester.pumpAndSettle();

      // Sender role on Ready for Handoff: shows View Handoff Code
      expect(find.text('View Handoff OTP / QR Code'), findsOneWidget);

      // Switch to Traveller role
      await tester.tap(find.widgetWithText(ChoiceChip, 'Traveller / Carrier'));
      await tester.pumpAndSettle();

      // Select Payment Secured for Traveller
      await tester.tap(find.widgetWithText(ChoiceChip, '1. Payment Secured'));
      await tester.pumpAndSettle();

      // Traveller role on Payment Secured: shows start delivery action
      expect(find.textContaining('start delivery'), findsWidgets);
    });

    testWidgets('SimulatedDeliveryRepository methods run completely offline', (tester) async {
      final repo = SimulatedDeliveryRepository();
      final sec = await repo.fetchHandoffSecret('fixture-handoff');
      expect(sec.otp, '849201');
      expect(sec.qrPayload, contains('shipdehop://handoff/'));

      await repo.verifyHandoffOtp('fixture-handoff', '849201');
      final completed = await repo.fetchDeliveryDetails('fixture-handoff', 'sender-1');
      expect(completed.lifecycleContext.escrowStatus, 'RELEASED');
    });
  });
}
