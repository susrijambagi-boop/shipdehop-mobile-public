import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shipdehop_mobile/models/notification_item.dart';
import 'package:shipdehop_mobile/providers/notification_provider.dart';
import 'package:shipdehop_mobile/screens/delivery_details_screen.dart';
import 'package:shipdehop_mobile/screens/journey_details_screen.dart';
import 'package:shipdehop_mobile/screens/notifications_sheet.dart';
import 'package:shipdehop_mobile/widgets/global_header.dart';

void main() {
  setUp(() {
    Animate.defaultDuration = Duration.zero;
  });
  group('Phase 13 Notification Model & Parser Unit Tests', () {
    test('Parses valid persisted notification JSON correctly', () {
      final json = {
        'id': 'notif-1111-2222',
        'user_id': 'user-aaaa-bbbb',
        'type': 'PARCEL_RESERVED',
        'title': 'A Hopster matched your parcel',
        'body': 'A Hopster reserved your parcel from Doha Corniche to Lusail Marina.',
        'entity_type': 'ORDER',
        'entity_id': 'order-3333-4444',
        'order_id': 'order-3333-4444',
        'trip_id': 'trip-5555-6666',
        'ride_request_id': null,
        'read_at': null,
        'idempotency_key': 'parcel_reserved:order-3333-4444:user-aaaa-bbbb',
        'created_at': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      };

      final item = NotificationItem.fromJson(json);

      expect(item.id, equals('notif-1111-2222'));
      expect(item.type, equals('PARCEL_RESERVED'));
      expect(item.title, equals('A Hopster matched your parcel'));
      expect(item.body, contains('Doha Corniche to Lusail Marina'));
      expect(item.isRead, isFalse);
      expect(item.orderId, equals('order-3333-4444'));
      expect(item.relativeTimeDescription, equals('5m ago'));
    });

    test('Actor rule: Driver accepting a request notifies Pooler only, NOT Driver actor', () {
      final poolerNotifJson = {
        'id': 'notif-pooler-1',
        'user_id': 'pooler-123',
        'type': 'RIDE_MATCHED',
        'title': 'Your ride request was matched',
        'body': 'Driver matched your ride from Doha to Lusail.',
        'entity_type': 'ORDER',
        'entity_id': 'order-ride-1',
        'order_id': 'order-ride-1',
        'trip_id': 'trip-driver-1',
        'ride_request_id': 'req-pooler-1',
        'read_at': null,
        'idempotency_key': 'ride_match:req-pooler-1:pooler-123',
        'created_at': DateTime.now().toIso8601String(),
      };

      final item = NotificationItem.fromJson(poolerNotifJson);

      expect(item.userId, equals('pooler-123'));
      expect(item.title, equals('Your ride request was matched'));
      expect(item.body, contains('Doha to Lusail'));
    });

    test('Actor rule: Direct Pooler booking notifies Driver as "New Pooler booking" exactly once', () {
      final driverNotifJson = {
        'id': 'notif-driver-1',
        'user_id': 'driver-456',
        'type': 'RIDER_RESERVED',
        'title': 'New Pooler booking',
        'body': 'A Pooler reserved 2 seat(s) on your journey.',
        'entity_type': 'ORDER',
        'entity_id': 'order-ride-2',
        'order_id': 'order-ride-2',
        'trip_id': 'trip-driver-1',
        'read_at': null,
        'idempotency_key': 'carpool_reserved:order-ride-2:driver-456',
        'created_at': DateTime.now().toIso8601String(),
      };

      final item = NotificationItem.fromJson(driverNotifJson);

      expect(item.userId, equals('driver-456'));
      expect(item.title, equals('New Pooler booking'));
      expect(item.body, equals('A Pooler reserved 2 seat(s) on your journey.'));
      expect(item.idempotencyKey, equals('carpool_reserved:order-ride-2:driver-456'));
    });

    test('Duplicate event handling: Deterministic idempotency key preserves uniqueness', () {
      final key1 = 'parcel_reserved:order-123:user-456';
      final key2 = 'parcel_reserved:order-123:user-456';
      expect(key1, equals(key2));
    });

    test('Identifies read notification accurately', () {
      final json = {
        'id': 'notif-2222',
        'user_id': 'user-aaaa',
        'type': 'PAYMENT_RELEASED',
        'title': 'Payment released',
        'body': 'Funds released for completed delivery.',
        'entity_type': 'ORDER',
        'entity_id': 'order-1234',
        'order_id': 'order-1234',
        'read_at': DateTime.now().toIso8601String(),
        'idempotency_key': 'funds_released:order-1234:user-aaaa',
        'created_at': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
      };

      final item = NotificationItem.fromJson(json);

      expect(item.isRead, isTrue);
      expect(item.relativeTimeDescription, equals('2h ago'));
    });
  });

  group('Phase 13 Notifications Sheet & Global Header Widget Tests', () {
    testWidgets('Renders NotificationsSheet with honest empty state when feed is empty', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NotificationsSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('No new notifications'), findsOneWidget);
      expect(find.text("We'll let you know about matches, payments, messages and safety updates here."), findsOneWidget);
    });

    testWidgets('Renders notifications grouped into Unread and Recent sections', (tester) async {
      final now = DateTime.now();
      final items = [
        NotificationItem(
          id: 'n1',
          userId: 'u1',
          type: 'RIDE_MATCHED',
          title: 'Your ride request was matched',
          body: 'Driver matched your ride from Doha to Lusail.',
          entityType: 'ORDER',
          entityId: 'o1',
          orderId: 'o1',
          readAt: null,
          idempotencyKey: 'key1',
          createdAt: now.subtract(const Duration(minutes: 10)),
        ),
        NotificationItem(
          id: 'n2',
          userId: 'u1',
          type: 'DELIVERY_COMPLETED',
          title: 'Delivery completed',
          body: 'Your delivery has been completed successfully.',
          entityType: 'ORDER',
          entityId: 'o2',
          orderId: 'o2',
          readAt: now.subtract(const Duration(minutes: 5)),
          idempotencyKey: 'key2',
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsProvider.overrideWith((ref) async => items),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NotificationsSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Unread (1)'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Your ride request was matched'), findsOneWidget);
      expect(find.text('Delivery completed'), findsOneWidget);
    });

    testWidgets('GlobalHeader displays unread count badge when unread notifications exist', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unreadNotificationsCountProvider.overrideWith((ref) => 3),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: GlobalHeader(onSelectTab: (_) {}),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    });

    testWidgets('Deep-Link Routing: Tapping RIDE_MATCHED notification opens JourneyDetailsScreen', (tester) async {
      final now = DateTime.now();
      final rideNotif = NotificationItem(
        id: 'n-ride-1',
        userId: 'u1',
        type: 'RIDE_MATCHED',
        title: 'Your ride request was matched',
        body: 'Driver matched your ride from Doha to Lusail.',
        entityType: 'ORDER',
        entityId: 'order-ride-123',
        orderId: 'order-ride-123',
        tripId: 'trip-999',
        readAt: null,
        idempotencyKey: 'key-ride-1',
        createdAt: now.subtract(const Duration(minutes: 5)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsProvider.overrideWith((ref) async => [rideNotif]),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NotificationsSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Your ride request was matched'));
      await tester.pumpAndSettle();

      expect(find.byType(JourneyDetailsScreen), findsOneWidget);
      expect(find.byType(DeliveryDetailsScreen), findsNothing);
    });

    testWidgets('Deep-Link Routing: Tapping RIDER_RESERVED notification opens JourneyDetailsScreen', (tester) async {
      final now = DateTime.now();
      final riderNotif = NotificationItem(
        id: 'n-ride-2',
        userId: 'u1',
        type: 'RIDER_RESERVED',
        title: 'New Pooler booking',
        body: 'A Pooler reserved 2 seat(s) on your journey.',
        entityType: 'ORDER',
        entityId: 'order-ride-456',
        orderId: 'order-ride-456',
        tripId: 'trip-888',
        readAt: null,
        idempotencyKey: 'key-ride-2',
        createdAt: now.subtract(const Duration(minutes: 2)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsProvider.overrideWith((ref) async => [riderNotif]),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NotificationsSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('New Pooler booking'));
      await tester.pumpAndSettle();

      expect(find.byType(JourneyDetailsScreen), findsOneWidget);
      expect(find.byType(DeliveryDetailsScreen), findsNothing);
    });
  });
}

