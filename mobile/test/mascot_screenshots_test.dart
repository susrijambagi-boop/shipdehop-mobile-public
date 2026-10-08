import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shipdehop_mobile/screens/onboarding_screen.dart';
import 'package:shipdehop_mobile/screens/sign_in_screen.dart';
import 'package:shipdehop_mobile/screens/live_tracking_screen.dart';
import 'package:shipdehop_mobile/screens/chat_inbox_screen.dart';
import 'package:shipdehop_mobile/screens/chat_screen.dart';
import 'package:shipdehop_mobile/screens/notifications_sheet.dart';
import 'package:shipdehop_mobile/widgets/mascot/mascot_loading.dart';
import 'package:shipdehop_mobile/widgets/mascot/mascot_success.dart';
import 'package:shipdehop_mobile/widgets/mascot/mascot_empty_state.dart';
import 'package:shipdehop_mobile/providers/app_providers.dart';
import 'package:shipdehop_mobile/providers/phase15_providers.dart';

void main() {
  if (Platform.environment['EXPORT_PNG'] != 'true') return;
  TestWidgetsFlutterBinding.ensureInitialized();
  Animate.defaultDuration = Duration.zero;

  Future<void> captureWidget({
    required WidgetTester tester,
    required Widget widget,
    required String filename,
    Size size = const Size(390, 844),
  }) async {
    FlutterError.onError = (details) {};

    tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
    tester.view.devicePixelRatio = 2.0;

    final GlobalKey repaintKey = GlobalKey();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(null)),
          unifiedHistoryProvider.overrideWith((ref) => []),
          userOrdersProvider.overrideWith((ref) => []),
          marketplaceFeedProvider.overrideWith((ref) => []),
          shipmentFeedProvider.overrideWith((ref) => []),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'Inter',
            useMaterial3: true,
          ),
          home: Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: RepaintBoundary(
              key: repaintKey,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: widget,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    try {
      final BuildContext context = repaintKey.currentContext!;
      final RenderRepaintBoundary boundary = context.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      final dir = Directory('ux_review');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final file = File('ux_review/$filename');
      file.writeAsBytesSync(pngBytes);
      debugPrint('EXPORTED MASCOT SCREENSHOT: $filename');
    } catch (e) {
      debugPrint('ERROR exporting $filename: $e');
    }
  }

  testWidgets('mascot_loading', (tester) async {
    await captureWidget(
      tester: tester,
      widget: const MascotLoadingOverlay(
        title: 'Getting your hops ready…',
        subtitle: 'Connecting to secure ShipdeHop session',
      ),
      filename: 'mascot_loading.png',
    );
  });

  testWidgets('mascot_onboarding_1', (tester) async {
    await captureWidget(
      tester: tester,
      widget: const OnboardingScreen(initialPage: 0),
      filename: 'mascot_onboarding_1.png',
    );
  });

  testWidgets('mascot_onboarding_2', (tester) async {
    await captureWidget(
      tester: tester,
      widget: const OnboardingScreen(initialPage: 1),
      filename: 'mascot_onboarding_2.png',
    );
  });

  testWidgets('mascot_onboarding_3', (tester) async {
    await captureWidget(
      tester: tester,
      widget: const OnboardingScreen(initialPage: 2),
      filename: 'mascot_onboarding_3.png',
    );
  });

  testWidgets('mascot_login', (tester) async {
    await captureWidget(
      tester: tester,
      widget: const SignInScreen(),
      filename: 'mascot_login.png',
    );
  });

  testWidgets('mascot_order_confirmed', (tester) async {
    await captureWidget(
      tester: tester,
      widget: MascotSuccessModal(
        title: 'Order Confirmed!',
        subtitle: 'Your traveller has been assigned and escrow is locked with HopPay.',
        secondaryDetail: 'HopShield & HopPay protection active',
        buttonLabel: 'View Order Details',
        onDismiss: () {},
      ),
      filename: 'mascot_order_confirmed.png',
    );
  });

  testWidgets('mascot_live_tracking', (tester) async {
    await captureWidget(
      tester: tester,
      widget: const LiveTrackingScreen(
        tripId: 'trip-1',
        driverMode: false,
        isParcel: true,
      ),
      filename: 'mascot_live_tracking.png',
    );
  });

  testWidgets('mascot_chat_inbox', (tester) async {
    await captureWidget(
      tester: tester,
      widget: const ChatInboxScreen(),
      filename: 'mascot_chat_inbox.png',
    );
  });

  testWidgets('mascot_chat', (tester) async {
    await captureWidget(
      tester: tester,
      widget: const ChatScreen(
        threadId: 'thread-1',
        orderId: '017e03ce-7280-433c-82d3-f3c2c4bb5a7f',
      ),
      filename: 'mascot_chat.png',
    );
  });

  testWidgets('mascot_notifications', (tester) async {
    await captureWidget(
      tester: tester,
      widget: const NotificationsSheet(),
      filename: 'mascot_notifications.png',
    );
  });

  testWidgets('mascot_empty_state', (tester) async {
    await captureWidget(
      tester: tester,
      widget: MascotEmptyState.noRides(),
      filename: 'mascot_empty_state.png',
    );
  });
}
