import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shipdehop_mobile/models/notification_item.dart';
import 'package:shipdehop_mobile/providers/notification_provider.dart';
import 'package:shipdehop_mobile/screens/journey_details_screen.dart';
import 'package:shipdehop_mobile/screens/main_home_screen.dart';

void main() {
  testWidgets('PHASE 13.3 — Trace RIDE_MATCHED Notification Tap Flow', (tester) async {
    final now = DateTime.now();
    final realRideNotif = NotificationItem(
      id: '90c0e3ea-3efa-4086-812b-c05637189dd0',
      userId: 'ed9517fc-7ebe-437c-bdc0-abb45bef9079',
      type: 'RIDE_MATCHED',
      title: 'Your ride request was matched',
      body: 'Driver matched your ride from Doha Corniche to Lusail Marina.',
      entityType: 'ORDER',
      entityId: '04b828b4-b9ff-4037-bc00-5265c172fc34',
      orderId: '04b828b4-b9ff-4037-bc00-5265c172fc34',
      tripId: '1b7a6df7-5f89-46de-a9ed-751ab3d48eb4',
      rideRequestId: 'f2b799e0-d6c9-43c6-848c-76341499dc70',
      readAt: null,
      idempotencyKey: 'ride_match:f2b799e0-d6c9-43c6-848c-76341499dc70:ed9517fc-7ebe-437c-bdc0-abb45bef9079',
      createdAt: now.subtract(const Duration(minutes: 5)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsProvider.overrideWith((ref) async => [realRideNotif]),
        ],
        child: const MaterialApp(
          home: MainHomeScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 1. Tap bell icon in GlobalHeader to open NotificationsSheet
    final bellFinder = find.byIcon(Icons.notifications_none_rounded);
    expect(bellFinder, findsOneWidget);
    await tester.tap(bellFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 2. NotificationsSheet should be visible
    expect(find.text('Your ride request was matched'), findsOneWidget);

    // 3. Tap the RIDE_MATCHED notification tile
    await tester.tap(find.text('Your ride request was matched'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(JourneyDetailsScreen), findsOneWidget);
  });
}
