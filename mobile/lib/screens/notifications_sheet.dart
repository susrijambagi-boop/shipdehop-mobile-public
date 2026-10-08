import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/confirmed_location.dart';
import '../models/date_flexibility.dart';
import '../models/journey.dart';
import '../models/notification_item.dart';
import '../providers/app_providers.dart';
import '../providers/notification_provider.dart';
import '../widgets/mascot/mascot_motion.dart';
import '../widgets/mascot/mascot_pose.dart';
import '../widgets/mascot/shipdehop_mascot.dart';
import 'delivery_details_screen.dart';
import 'journey_details_screen.dart';
import 'marketplace_order_detail_screen.dart';

class NotificationsSheet extends ConsumerWidget {
  const NotificationsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_outlined, color: Color(0xFF312E81), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Notifications',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E1B4B),
                      ),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.done_all, size: 14),
                  label: const Text('Mark all read', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () async {
                    await NotificationActions(ref).markAllRead();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: notificationsAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return _buildEmptyState(context);
                }
                final visibleItems = _dedupeForDisplay(items);
                final unread = visibleItems.where((i) => !i.isRead).toList();
                final read = visibleItems.where((i) => i.isRead).toList();

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (unread.isNotEmpty) ...[
                      _buildSectionHeader(context, 'Unread (${unread.length})'),
                      ...unread.map((item) => _buildNotificationTile(context, ref, item)),
                      const SizedBox(height: 16),
                    ],
                    if (read.isNotEmpty) ...[
                      _buildSectionHeader(context, 'Recent'),
                      ...read.map((item) => _buildNotificationTile(context, ref, item)),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => _buildEmptyState(context),
            ),
          ),
        ],
      ),
    );
  }

  List<NotificationItem> _dedupeForDisplay(List<NotificationItem> items) {
    final seen = <String>{};
    final result = <NotificationItem>[];
    for (final item in items) {
      final key = '${item.type}|${item.orderId ?? ''}|${item.tripId ?? ''}|${item.title}|${item.body}';
      if (seen.add(key)) result.add(item);
    }
    return result;
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildNotificationTile(
    BuildContext context,
    WidgetRef ref,
    NotificationItem item,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: item.isRead ? 0 : 1,
      color: item.isRead ? Colors.grey.shade50 : const Color(0xFFEEF2FF),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: item.isRead ? Colors.grey.shade300 : const Color(0xFFC7D2FE),
          child: Icon(
            _getNotificationIcon(item.type),
            color: item.isRead ? Colors.grey.shade700 : const Color(0xFF312E81),
            size: 20,
          ),
        ),
        title: Text(
          item.title,
          style: TextStyle(
            fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              item.body,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 4),
            Text(
              item.relativeTimeDescription,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
        onTap: () async {
          final navigator = Navigator.of(context);
          final scaffoldMessenger = ScaffoldMessenger.of(context);

          if (!item.isRead) {
            try {
              await NotificationActions(ref).markRead(item.id);
            } catch (_) {}
          }

          final route = await _resolveTargetRoute(ref, item);

          if (route != null) {
            navigator.pop();
            navigator.push<void>(route);
          } else {
            navigator.pop();
            scaffoldMessenger.showSnackBar(
              SnackBar(
                content: Text('Unable to resolve details for notification "${item.title}"'),
                backgroundColor: Colors.amber.shade900,
              ),
            );
          }
        },
      ),
    );
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'RIDE_MATCHED':
      case 'RIDER_RESERVED':
        return Icons.directions_car;
      case 'PARCEL_RESERVED':
      case 'DELIVERY_STARTED':
      case 'HANDOFF_VERIFIED':
      case 'DELIVERY_COMPLETED':
        return Icons.local_shipping;
      case 'PAYMENT_SECURED':
      case 'PAYMENT_RELEASED':
        return Icons.account_balance_wallet;
      case 'ORDER_CANCELLED':
        return Icons.cancel;
      default:
        return Icons.notifications;
    }
  }

  Future<Route<void>?> _resolveTargetRoute(
    WidgetRef ref,
    NotificationItem item,
  ) async {
    if (item.type == 'RIDE_MATCHED' || item.type == 'RIDER_RESERVED') {
      return _buildRideRoute(ref, item);
    }

    if (item.type == 'MARKETPLACE_PURCHASED') {
      if (item.orderId != null) {
        return MaterialPageRoute<void>(
          builder: (_) => MarketplaceOrderDetailScreen(orderId: item.orderId!),
        );
      }
    }

    if (item.type == 'PARCEL_RESERVED' ||
        item.type == 'DELIVERY_STARTED' ||
        item.type == 'DELIVERY_COMPLETED') {
      if (item.orderId != null) {
        return MaterialPageRoute<void>(
          builder: (_) => DeliveryDetailsScreen(orderId: item.orderId!),
        );
      }
      if (item.tripId != null) {
        return _buildRideRoute(ref, item);
      }
      return null;
    }

    if (item.orderId != null) {
      final orderType = await _resolveOrderType(ref, item.orderId!);
      if (orderType == 'RIDE') {
        return _buildRideRoute(ref, item);
      } else if (orderType == 'MARKETPLACE') {
        return MaterialPageRoute<void>(
          builder: (_) => MarketplaceOrderDetailScreen(orderId: item.orderId!),
        );
      } else {
        return MaterialPageRoute<void>(
          builder: (_) => DeliveryDetailsScreen(orderId: item.orderId!),
        );
      }
    }

    if (item.tripId != null) {
      return _buildRideRoute(ref, item);
    }

    return null;
  }

  Future<Route<void>> _buildRideRoute(
    WidgetRef ref,
    NotificationItem item,
  ) async {
    String? tripId = item.tripId;

    if (tripId == null && item.orderId != null) {
      try {
        final client = ref.read(supabaseProvider);
        final orderRow = await client
            .from('escrow_orders')
            .select('trip_id')
            .eq('id', item.orderId!)
            .maybeSingle();
        if (orderRow != null && orderRow['trip_id'] != null) {
          tripId = orderRow['trip_id'] as String;
        }
      } catch (_) {}
    }

    Journey? journey;
    if (tripId != null) {
      try {
        final client = ref.read(supabaseProvider);
        final tripRow = await client
            .from('trip_routes')
            .select('*')
            .eq('id', tripId)
            .maybeSingle();
        if (tripRow != null) {
          journey = _buildJourneyFromTripRow(tripRow);
        }
      } catch (_) {}
    }

    final targetId = tripId ?? 'journey-doha-lusail';
    journey ??= _buildFallbackJourney(targetId);

    return MaterialPageRoute<void>(
      builder: (_) => JourneyDetailsScreen(journey: journey!),
    );
  }

  Future<String> _resolveOrderType(WidgetRef ref, String orderId) async {
    try {
      final client = ref.read(supabaseProvider);
      final row = await client
          .from('escrow_orders')
          .select('order_type')
          .eq('id', orderId)
          .maybeSingle();
      if (row != null && row['order_type'] != null) {
        return (row['order_type'] as String).toUpperCase();
      }
    } catch (_) {}
    return 'SHIPMENT';
  }

  Journey _buildJourneyFromTripRow(Map<String, dynamic> row) {
    final departureStr = row['departure_time'] as String?;
    final departureTime = departureStr != null ? DateTime.tryParse(departureStr) ?? DateTime.now() : DateTime.now();

    return Journey(
      id: row['id'] as String? ?? 'journey-1',
      origin: ConfirmedLocation(
        displayLabel: row['origin_name'] as String? ?? 'Trip Origin',
        formattedAddress: row['origin_name'] as String? ?? 'Trip Origin Address',
        latitude: 25.2854,
        longitude: 51.5310,
      ),
      destination: ConfirmedLocation(
        displayLabel: row['dest_name'] as String? ?? 'Trip Destination',
        formattedAddress: row['dest_name'] as String? ?? 'Trip Destination Address',
        latitude: 25.4184,
        longitude: 51.5310,
      ),
      timing: DateFlexibility(
        earliestDateTime: departureTime,
        latestDateTime: departureTime.add(const Duration(hours: 12)),
      ),
      travellerName: 'Verified Driver',
      seatCapacity: (row['seat_capacity'] as num?)?.toInt() ?? 4,
      availableSeats: (row['available_seats'] as num?)?.toInt() ?? 2,
      acceptsParcels: true,
      parcelCapacityTier: row['parcel_capacity_tier'] as String? ?? 'MEDIUM',
      parcelCapacityUnitsTotal: (row['parcel_capacity_units_total'] as num?)?.toInt() ?? 6,
      parcelCapacityUnitsAvailable: (row['parcel_capacity_units_available'] as num?)?.toInt() ?? 5,
      acceptsShoppingRequests: true,
      pricePerSeat: (row['price_per_seat'] as num?)?.toDouble() ?? 25.0,
      currency: row['currency'] as String? ?? 'INR',
      jurisdictionCode: row['jurisdiction_code'] as String? ?? 'IN',
      status: row['status'] as String? ?? 'SCHEDULED',
    );
  }

  Journey _buildFallbackJourney(String tripId) {
    final now = DateTime.now();
    return Journey(
      id: tripId,
      origin: const ConfirmedLocation(
        displayLabel: 'Trip Origin',
        formattedAddress: 'Trip Origin Address',
        latitude: 25.2854,
        longitude: 51.5310,
      ),
      destination: const ConfirmedLocation(
        displayLabel: 'Trip Destination',
        formattedAddress: 'Trip Destination Address',
        latitude: 25.4184,
        longitude: 51.5310,
      ),
      timing: DateFlexibility(
        earliestDateTime: now.add(const Duration(hours: 2)),
        latestDateTime: now.add(const Duration(hours: 14)),
      ),
      travellerName: 'Verified Driver',
      seatCapacity: 4,
      availableSeats: 2,
      acceptsParcels: true,
      parcelCapacityTier: 'MEDIUM',
      parcelCapacityUnitsTotal: 6,
      parcelCapacityUnitsAvailable: 5,
      acceptsShoppingRequests: true,
      pricePerSeat: 0.0,
      currency: 'INR',
      jurisdictionCode: 'IN',
      status: 'SCHEDULED',
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShipdeHopMascot(
              pose: MascotPose.ringBell,
              motion: MascotMotion.idleFloat,
              size: 110,
            ),
            SizedBox(height: 12),
            Text(
              'No new notifications',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E1B4B),
              ),
            ),
            SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                "We'll let you know about matches, payments, messages and safety updates here.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
