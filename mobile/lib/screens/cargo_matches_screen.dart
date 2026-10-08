import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../providers/app_providers.dart';
import 'orders_screen.dart';

class CargoMatchesScreen extends ConsumerStatefulWidget {
  const CargoMatchesScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<CargoMatchesScreen> createState() => _CargoMatchesScreenState();
}

class _CargoMatchesScreenState extends ConsumerState<CargoMatchesScreen> {
  int maxDetourMeters = 5000;
  late Future<List<Map<String, dynamic>>> _matchesFuture;
  Map<String, dynamic>? _selectedCandidate;
  bool _reserving = false;

  @override
  void initState() {
    super.initState();
    _matchesFuture = _loadMatches();
  }

  Future<List<Map<String, dynamic>>> _loadMatches() async {
    final rows = await ref.read(supabaseProvider).rpc<List<dynamic>>(
      'match_shipments_along_route',
      params: {
        'p_trip_id': widget.tripId,
        'p_max_detour_meters': maxDetourMeters,
      },
    );
    return rows.cast<Map<String, dynamic>>();
  }

  void _refresh() {
    setState(() {
      _matchesFuture = _loadMatches();
    });
  }

  Future<void> _reserveShipmentCandidate(Map<String, dynamic> item) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to reserve a shipment.')),
      );
      return;
    }

    setState(() => _reserving = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await ref.read(apiClientProvider).post('/orders/reserve', {
        'type': 'SHIPMENT',
        'shipmentTaskId': item['shipment_task_id'].toString(),
        'providerId': userId,
        'tripId': widget.tripId,
      });

      final orderMap = (result['order'] as Map).cast<String, dynamic>();

      if (!mounted) return;
      Navigator.pop(context); // Close candidate detail modal

      _showOrderCreatedSummaryDialog(orderMap);
      _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Reservation failed: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error reserving shipment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reserving = false);
    }
  }

  void _showOrderCreatedSummaryDialog(Map<String, dynamic> order) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Shipment Reserved!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Escrow Order Created (PENDING)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _detailRow('Order ID', '${order['id']}'),
            _detailRow('Order Type', '${order['order_type']}'),
            _detailRow('Currency', '${order['currency']}'),
            _detailRow('Reward Fee', '${order['currency']} ${order['reward_fee']}'),
            _detailRow('Platform Fee', '${order['currency']} ${order['platform_fee']}'),
            _detailRow('Total Amount', '${order['currency']} ${order['total_amount']}'),
            _detailRow('Escrow Status', '${order['escrow_status']}'),
            if (order['reservation_expires_at'] != null)
              _detailRow(
                'Expires At',
                DateTime.parse(order['reservation_expires_at'].toString())
                    .toLocal()
                    .toString()
                    .substring(0, 16),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.payment, color: Colors.amber, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Buyer Payment Required\nThe sender must fund the order within 30 minutes to lock escrow.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.brown),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => const OrdersScreen()),
              );
            },
            icon: const Icon(Icons.receipt_long),
            label: const Text('View in Orders'),
          ),
        ],
      ),
    );
  }

  void _inspectCandidateDetail(Map<String, dynamic> item) {
    setState(() {
      _selectedCandidate = item;
    });

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Candidate Shipment (${item['item_type'] ?? 'PARCEL'})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Corridor Match Summary',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              _detailRow('Shipment ID', '${item['shipment_task_id']}'),
              _detailRow('Item Type', '${item['item_type']}'),
              _detailRow('Weight', '${item['weight_kg']} kg'),
              _detailRow('Declared Value', '${item['currency']} ${item['declared_value']}'),
              _detailRow('Carrier Reward', '${item['currency']} ${item['reward_amount']}'),
              _detailRow(
                'Pickup Detour',
                NumberFormatLite.meters(item['pickup_distance_m']),
              ),
              _detailRow(
                'Drop Detour',
                NumberFormatLite.meters(item['drop_distance_m']),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Inspection Status: APPROVED\nEligible for Route Reservation',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Reserving creates a 30-minute pending escrow order. Sender must fund the payment before transit.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: _reserving ? null : () => _reserveShipmentCandidate(item),
              icon: _reserving
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bookmark_add_outlined),
              label: Text(_reserving ? 'Reserving...' : 'Reserve Shipment'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Corridor Parcel Matches'),
        actions: [
          IconButton(
            tooltip: 'Refresh Matches',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Max Route Detour:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                DropdownButton<int>(
                  value: maxDetourMeters,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 1000, child: Text('1 km')),
                    DropdownMenuItem(value: 3000, child: Text('3 km')),
                    DropdownMenuItem(value: 5000, child: Text('5 km (Default)')),
                    DropdownMenuItem(value: 10000, child: Text('10 km')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        maxDetourMeters = v;
                        _matchesFuture = _loadMatches();
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _matchesFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Searching corridor for approved HopShip parcels...'),
                      ],
                    ),
                  );
                }

                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 12),
                          Text(
                            'Failed to load matches: ${snap.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final rows = snap.data ?? [];
                if (rows.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView(
                      padding: const EdgeInsets.all(32),
                      children: [
                        const SizedBox(height: 40),
                        const Icon(Icons.search_off_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text(
                          'No Parcel Matches Found Along Corridor',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No approved HopShip parcel pickup + drop-off pair currently fits this route corridor within ${NumberFormatLite.meters(maxDetourMeters)} detour tolerance.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh Corridor Search'),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final isSelected = _selectedCandidate?['shipment_task_id'] == r['shipment_task_id'];

                      return Card(
                        elevation: isSelected ? 4 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isSelected
                              ? const BorderSide(color: Colors.blue, width: 2)
                              : BorderSide.none,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: const Icon(Icons.luggage_outlined),
                          ),
                          title: Text(
                            '${r['item_type']} • ${r['weight_kg']} kg',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                'Pickup: ${NumberFormatLite.meters(r['pickup_distance_m'])} detour',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                'Drop-off: ${NumberFormatLite.meters(r['drop_distance_m'])} detour',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${r['currency']} ${r['reward_amount']}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              const Text(
                                'Carrier Reward',
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                          onTap: () => _inspectCandidateDetail(r),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class NumberFormatLite {
  static String meters(Object? v) {
    final n = (v as num?)?.toDouble() ?? 0;
    return n >= 1000 ? '${(n / 1000).toStringAsFixed(1)} km' : '${n.round()} m';
  }
}
