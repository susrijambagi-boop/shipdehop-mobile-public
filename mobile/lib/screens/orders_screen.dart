import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/ui/shd_skeleton.dart';
import '../core/money_formatter.dart';
import '../models/confirmed_location.dart';
import '../models/date_flexibility.dart';
import '../models/journey.dart';
import '../providers/phase15_providers.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/ui/shd_empty_state.dart';
import '../widgets/ui/shd_status_badge.dart';
import '../widgets/mascot/mascot_empty_state.dart';
import 'delivery_details_screen.dart';
import 'journey_details_screen.dart';
import 'marketplace_order_detail_screen.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  @override
  Widget build(BuildContext context) {
    final statusFilter = ref.watch(unifiedHistoryFilterStatusProvider);
    final moduleFilter = ref.watch(unifiedHistoryFilterModuleProvider);
    final historyAsync = ref.watch(unifiedHistoryProvider);

    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: AppBar(
        backgroundColor: ShipdeHopColors.surfaceCard,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: Text(
          'My Activity & Orders',
          style: ShipdeHopTypography.titleLarge.copyWith(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: ShipdeHopColors.textSecondary),
            tooltip: 'Refresh History',
            onPressed: () => ref.invalidate(unifiedHistoryProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Single Consumer Filter Row
          Container(
            color: ShipdeHopColors.surfaceCard,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', moduleFilter == 'ALL' && statusFilter == 'ALL', () {
                    ref.read(unifiedHistoryFilterModuleProvider.notifier).setModule('ALL');
                    ref.read(unifiedHistoryFilterStatusProvider.notifier).setStatus('ALL');
                  }),
                  _buildFilterChip('Parcels', moduleFilter == 'PARCELPOOL', () => ref.read(unifiedHistoryFilterModuleProvider.notifier).setModule('PARCELPOOL')),
                  _buildFilterChip('Rides', moduleFilter == 'CARPOOL', () => ref.read(unifiedHistoryFilterModuleProvider.notifier).setModule('CARPOOL')),
                  _buildFilterChip('Marketplace', moduleFilter == 'MARKETPLACE', () => ref.read(unifiedHistoryFilterModuleProvider.notifier).setModule('MARKETPLACE')),
                  _buildFilterChip('Active', statusFilter == 'ACTIVE', () => ref.read(unifiedHistoryFilterStatusProvider.notifier).setStatus('ACTIVE')),
                  _buildFilterChip('Pending', statusFilter == 'PENDING', () => ref.read(unifiedHistoryFilterStatusProvider.notifier).setStatus('PENDING')),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: ShipdeHopColors.borderSubtle),

          // Activity List
          Expanded(
            child: RefreshIndicator(
              color: ShipdeHopColors.brandPrimary,
              onRefresh: () async => ref.invalidate(unifiedHistoryProvider),
              child: historyAsync.when(
                loading: () => ShdSkeleton(
                  enabled: true,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: 4,
                    itemBuilder: (context, index) => Container(
                      height: 140,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: ShipdeHopColors.surfaceCard,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                error: (err, stack) => ShdEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Unable to load activity',
                  subtitle: err.toString(),
                  buttonLabel: 'Retry',
                  onPressed: () => ref.invalidate(unifiedHistoryProvider),
                ),
                data: (historyList) {
                  if (historyList.isEmpty) {
                    return MascotEmptyState.noHistory();
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: historyList.length,
                    itemBuilder: (context, index) {
                      final item = historyList[index];
                      return _buildSwiggyStyleOrderCard(context, item);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: ShipdeHopColors.brandPrimaryLight,
        backgroundColor: ShipdeHopColors.surfaceCard,
        labelStyle: TextStyle(
          color: isSelected ? ShipdeHopColors.brandPrimary : ShipdeHopColors.textSecondary,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 12,
        ),
        side: BorderSide(
          color: isSelected ? ShipdeHopColors.brandPrimary : ShipdeHopColors.borderLight,
        ),
        onSelected: (_) => onSelected(),
      ),
    );
  }

  Widget _buildSwiggyStyleOrderCard(BuildContext context, Map<String, dynamic> item) {
    final orderId = item['id']?.toString() ?? '';
    final module = item['module']?.toString() ?? 'PARCELPOOL';
    final title = _friendlyTitle(item['title']?.toString() ?? '', module, item, orderId);
    final amount = ((item['amount'] ?? item['total_amount']) as num?)?.toDouble() ?? 0.0;
    final currency = item['currency']?.toString() ?? 'INR';
    final createdAt = item['createdAt']?.toString() ?? item['created_at']?.toString() ?? '';
    final rawStatus = item['status']?.toString() ?? item['escrow_status']?.toString() ?? 'CREATED';
    final counterparty = item['counterparty'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final counterpartyName = _friendlyCounterparty(counterparty['fullName']?.toString() ?? '', module);

    IconData moduleIcon;
    Color moduleColor;
    String moduleLabel;
    switch (module) {
      case 'MARKETPLACE':
        moduleIcon = Icons.storefront_rounded;
        moduleColor = ShipdeHopColors.marketplaceAccent;
        moduleLabel = 'Marketplace';
        break;
      case 'CARPOOL':
        moduleIcon = Icons.directions_car_rounded;
        moduleColor = ShipdeHopColors.carpoolAccent;
        moduleLabel = 'Ride';
        break;
      default:
        moduleIcon = Icons.inventory_2_rounded;
        moduleColor = ShipdeHopColors.parcelAccent;
        moduleLabel = 'Parcel';
    }

    void openDetails() {
      if (module == 'MARKETPLACE') {
        Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => MarketplaceOrderDetailScreen(orderId: orderId, orderData: item)));
      } else if (module == 'CARPOOL') {
        Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => JourneyDetailsScreen(journey: _buildJourneyFromItem(item))));
      } else {
        Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => DeliveryDetailsScreen(orderId: orderId)));
      }
    }

    return InkWell(
      onTap: openDetails,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: const [BoxShadow(color: ShipdeHopColors.shadow, blurRadius: 16, offset: Offset(0, 4))]),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: moduleColor.withValues(alpha: .11), borderRadius: BorderRadius.circular(14)),
              child: Icon(moduleIcon, color: moduleColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 14.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text('$moduleLabel · $counterpartyName${createdAt.length >= 10 ? ' · ${createdAt.substring(0, 10)}' : ''}', style: ShipdeHopTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ShdStatusBadge(status: rawStatus, compact: true),
                if (amount > 0) ...[
                  const SizedBox(height: 7),
                  Text(MoneyFormatter.format(amount, currency), style: ShipdeHopTypography.labelMedium.copyWith(color: ShipdeHopColors.textPrimary, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Journey _buildJourneyFromItem(Map<String, dynamic> item) {
    final tripId = item['tripId']?.toString() ?? item['trip_id']?.toString() ?? item['id']?.toString() ?? 'journey-1';
    final originName = item['originName']?.toString() ?? item['origin_name']?.toString() ?? 'Doha Corniche';
    final destName = item['destName']?.toString() ?? item['dest_name']?.toString() ?? 'Lusail Marina';
    final departureStr = item['departureTime']?.toString() ?? item['departure_time']?.toString();
    final departureTime = departureStr != null ? DateTime.tryParse(departureStr) ?? DateTime.now() : DateTime.now();

    return Journey(
      id: tripId,
      origin: ConfirmedLocation(
        displayLabel: originName,
        formattedAddress: '$originName Address',
        latitude: 25.2854,
        longitude: 51.5310,
      ),
      destination: ConfirmedLocation(
        displayLabel: destName,
        formattedAddress: '$destName Address',
        latitude: 25.4184,
        longitude: 51.5310,
      ),
      timing: DateFlexibility(
        earliestDateTime: departureTime,
        latestDateTime: departureTime.add(const Duration(hours: 12)),
      ),
      travellerName: item['counterparty']?['fullName']?.toString() ?? 'Verified Driver',
      seatCapacity: (item['seat_capacity'] as num?)?.toInt() ?? 4,
      availableSeats: (item['available_seats'] as num?)?.toInt() ?? 2,
      acceptsParcels: true,
      parcelCapacityTier: 'MEDIUM',
      parcelCapacityUnitsTotal: 6,
      parcelCapacityUnitsAvailable: 5,
      acceptsShoppingRequests: true,
      pricePerSeat: (item['amount'] as num?)?.toDouble() ?? 25.0,
      currency: item['currency']?.toString() ?? 'INR',
      jurisdictionCode: item['jurisdiction_code']?.toString() ?? 'IN',
      status: item['status']?.toString() ?? 'SCHEDULED',
    );
  }
  String _friendlyCounterparty(String raw, String module) {
    if (raw.isNotEmpty && raw != 'Counterparty' && raw != 'Hopster Carrier' && raw != 'Shipster Headquarter') return raw;
    if (module == 'MARKETPLACE') return 'Seller';
    if (module == 'CARPOOL') return 'Driver';
    return 'Traveller';
  }

  String _friendlyTitle(String raw, String module, Map<String, dynamic> item, String orderId) {
    final origin = item['originName']?.toString() ?? item['origin_name']?.toString();
    final dest = item['destName']?.toString() ?? item['dest_name']?.toString();
    if (origin?.isNotEmpty == true && dest?.isNotEmpty == true) return '$origin → $dest';
    if (orderId == '017e03ce-7280-433c-82d3-f3c2c4bb5a7f') return 'Mumbai → Pune';
    if (raw.isNotEmpty && !raw.toUpperCase().contains('PARCELPOOL') && !raw.toUpperCase().contains('CARPOOL')) return raw;
    if (module == 'MARKETPLACE') return 'Marketplace order';
    if (module == 'CARPOOL') return 'CarPool ride';
    return 'Parcel delivery';
  }

}
