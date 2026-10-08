import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_config.dart';
import '../core/delivery_lifecycle.dart';
import '../core/money_formatter.dart';
import '../providers/app_providers.dart';
import '../repositories/delivery_repository.dart';
import '../theme/shipdehop_colors.dart';
import '../theme/shipdehop_typography.dart';
import '../widgets/escrow_breakdown.dart';
import '../widgets/sender_handoff_modal.dart';
import '../widgets/traveller_handoff_modal.dart';
import 'chat_inbox_screen.dart';
import 'live_tracking_screen.dart';

class DeliveryDetailsScreen extends ConsumerStatefulWidget {
  const DeliveryDetailsScreen({super.key, required this.orderId, this.repository});
  final String orderId;
  final DeliveryRepository? repository;

  @override
  ConsumerState<DeliveryDetailsScreen> createState() => _DeliveryDetailsScreenState();
}

class _DeliveryDetailsScreenState extends ConsumerState<DeliveryDetailsScreen> {
  late DeliveryRepository _repository;
  late Future<DeliveryDetailsData> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _initRepository();
  }

  void _initRepository() {
    if (widget.repository != null) {
      _repository = widget.repository!;
    } else {
      final user = ref.read(authUserProvider).value;
      _repository = user == null && AppConfig.enableDevTestAuth
          ? SimulatedDeliveryRepository()
          : LiveDeliveryRepository(apiClient: ref.read(apiClientProvider), supabaseClient: ref.read(supabaseProvider));
    }
    final userId = ref.read(authUserProvider).value?.id;
    _detailsFuture = _repository.fetchDeliveryDetails(widget.orderId, userId);
  }

  void _loadDetails() {
    final userId = ref.read(authUserProvider).value?.id;
    final next = _repository.fetchDeliveryDetails(widget.orderId, userId);
    if (!mounted) {
      _detailsFuture = next;
      return;
    }
    setState(() {
      _detailsFuture = next;
    });
  }

  Future<void> _showPickupCodeModal() async {
    showDialog<void>(
      context: context,
      builder: (ctx) => FutureBuilder<HandoffSecretData>(
        future: _repository.fetchPickupSecret(widget.orderId),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())));
          }
          if (snapshot.hasError) {
            return AlertDialog(
              title: const Text('Error'),
              content: Text(snapshot.error.toString()),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
            );
          }
          final secret = snapshot.data!;
          return AlertDialog(
            title: const Text('Parcel Pickup Code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Provide this 6-digit code to the traveller when they arrive to collect the parcel:'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(color: ShipdeHopColors.brandPrimaryLight, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    secret.otp,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 6, color: ShipdeHopColors.brandPrimary),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Expires in ${secret.expiresInSeconds ~/ 60} minutes • Single-use', style: const TextStyle(fontSize: 11, color: ShipdeHopColors.textMuted)),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
          );
        },
      ),
    );
  }

  Future<void> _handleStartDelivery() async {
    final codeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter pickup code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the 6-digit code provided by the sender upon receiving the parcel:'),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '6-digit code',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: ShipdeHopColors.brandPrimary, foregroundColor: Colors.white),
            child: const Text('Verify & Start'),
          ),
        ],
      ),
    );
    if (ok != true || codeCtrl.text.trim().isEmpty) return;
    try {
      await _repository.confirmPickup(widget.orderId, pickupCode: codeCtrl.text.trim());
      _loadDetails();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openChat() => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const ChatInboxScreen()));

  Future<void> _openReportIssue() async {
    String category = 'OTHER';
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Report an issue'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select category:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: category,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'TRAVELLER_DID_NOT_ARRIVE', child: Text('Traveller did not arrive')),
                  DropdownMenuItem(value: 'SENDER_UNAVAILABLE', child: Text('Sender unavailable')),
                  DropdownMenuItem(value: 'PARCEL_MISMATCH', child: Text('Parcel mismatch / size issue')),
                  DropdownMenuItem(value: 'SAFETY_CONCERN', child: Text('Safety concern')),
                  DropdownMenuItem(value: 'DELIVERY_PROBLEM', child: Text('Delivery problem')),
                  DropdownMenuItem(value: 'OTHER', child: Text('Other issue')),
                ],
                onChanged: (val) => setDlgState(() => category = val ?? 'OTHER'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Provide details about the issue...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit Report'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && descCtrl.text.trim().isNotEmpty) {
      try {
        await _repository.reportIssue(widget.orderId, category, descCtrl.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Issue reported. ShipdeHop beta support will review this report.')),
          );
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _handleCancelOrder() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel match?'),
        content: const Text('Are you sure you want to cancel this match? Any reserved capacity will be restored.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, keep match')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await _repository.cancelOrder(widget.orderId);
        _loadDetails();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShipdeHopColors.background,
      appBar: AppBar(
        backgroundColor: ShipdeHopColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Delivery Details', style: ShipdeHopTypography.titleLarge.copyWith(fontSize: 21, fontWeight: FontWeight.w800)),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _loadDetails, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<DeliveryDetailsData>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _errorState(snapshot.error.toString());
          }

          final data = snapshot.data!;
          final order = data.order;
          final lifecycle = data.lifecycleContext;
          final state = DeliveryLifecycleMapper.resolveState(lifecycle);
          final orderType = order['order_type']?.toString().toUpperCase() ?? 'SHIPMENT';
          final tripId = order['trip_id']?.toString() ?? '';
          final currency = order['currency']?.toString() ?? 'INR';
          final total = ((order['total_amount'] ?? order['amount']) as num?)?.toDouble() ?? 0;
          final base = ((order['base_price'] ?? order['base_amount']) as num?)?.toDouble() ?? 0;
          final reward = ((order['reward_fee'] ?? order['reward_amount']) as num?)?.toDouble() ?? 0;
          final fee = (order['platform_fee'] as num?)?.toDouble() ?? 0;
          final routeTitle = _routeTitle(order, orderType);
          final isSender = lifecycle.role == ConsumerUserRole.sender || lifecycle.role == ConsumerUserRole.participant;
          final isCarrier = lifecycle.role == ConsumerUserRole.carrier;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: [
              _journeyHero(routeTitle, orderType, state),
              const SizedBox(height: 8),
              Text('Route & Pickup Locations', style: ShipdeHopTypography.labelSmall.copyWith(color: ShipdeHopColors.textMuted)),
              const SizedBox(height: 12),
              Text('Live Location Tracking', style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 14)),
              const SizedBox(height: 8),
              _mapHero(data, tripId, state, orderType),
              const SizedBox(height: 12),
              _currentStateCard(state, lifecycle, isSender, isCarrier, total, base, reward, fee, currency),
              const SizedBox(height: 12),
              Text('Payment Summary', style: ShipdeHopTypography.titleSmall.copyWith(fontSize: 14)),
              const SizedBox(height: 8),
              _hopPayCard(total, base, reward, fee, currency),
              const SizedBox(height: 12),
              _historyDisclosure(lifecycle),
            ],
          );
        },
      ),
    );
  }

  Widget _journeyHero(String routeTitle, String orderType, DeliveryLifecycleState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: ShipdeHopColors.brandPrimaryLight, borderRadius: BorderRadius.circular(15)),
          child: Icon(orderType == 'RIDE' ? Icons.directions_car_rounded : orderType == 'MARKETPLACE' ? Icons.shopping_bag_rounded : Icons.local_shipping_rounded, color: ShipdeHopColors.brandPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(routeTitle, style: ShipdeHopTypography.titleLarge.copyWith(fontSize: 18), maxLines: 2),
          const SizedBox(height: 4),
          Text(orderType == 'RIDE' ? 'CarPool ride' : orderType == 'MARKETPLACE' ? 'Marketplace delivery' : 'Parcel delivery', style: ShipdeHopTypography.bodySmall),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(color: DeliveryLifecycleMapper.getColor(state).withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
          child: Text(DeliveryLifecycleMapper.getTitle(state), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: DeliveryLifecycleMapper.getColor(state))),
        ),
      ]),
    );
  }

  Widget _mapHero(DeliveryDetailsData data, String tripId, DeliveryLifecycleState state, String orderType) {
    final tracking = data.trackingSnapshot;
    if (tracking != null && tracking.lat.abs() <= 90 && tracking.lon.abs() <= 180 && (tracking.lat != 0 || tracking.lon != 0)) {
      final point = ll.LatLng(tracking.lat, tracking.lon);
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: 310,
          child: Stack(children: [
            FlutterMap(
              options: MapOptions(initialCenter: point, initialZoom: 14.5),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'app.shipdehop.mobile'),
                MarkerLayer(markers: [
                  Marker(
                    point: point,
                    width: 48,
                    height: 48,
                    child: Container(
                      decoration: BoxDecoration(color: ShipdeHopColors.brandPrimary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                      child: Icon(orderType == 'RIDE' ? Icons.directions_car_rounded : Icons.local_shipping_rounded, color: Colors.white),
                    ),
                  ),
                ]),
              ],
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(color: ShipdeHopColors.brandDark.withValues(alpha: .94), borderRadius: BorderRadius.circular(18)),
                child: Row(children: [
                  const Icon(Icons.sensors_rounded, color: ShipdeHopColors.success),
                  const SizedBox(width: 9),
                  Expanded(child: Text('Live location · ${DeliveryLifecycleMapper.getTitle(state)}', style: ShipdeHopTypography.titleSmall.copyWith(color: Colors.white))),
                  if (tripId.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => LiveTrackingScreen(tripId: tripId, driverMode: false, isParcel: orderType != 'RIDE'))),
                      child: const Text('Open', style: TextStyle(color: Colors.white)),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      );
    }

    return Container(
      height: 178,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: ShipdeHopColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: ShipdeHopColors.brandPrimaryLight, borderRadius: BorderRadius.circular(17)),
            child: const Icon(Icons.map_outlined, color: ShipdeHopColors.brandPrimary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Live map will appear after pickup', style: ShipdeHopTypography.titleSmall),
                const SizedBox(height: 6),
                Text('We will show the real traveller location here as soon as a valid tracking signal is available.', style: ShipdeHopTypography.bodySmall),
                if (tripId.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => LiveTrackingScreen(tripId: tripId, driverMode: false, isParcel: orderType != 'RIDE'))),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open tracking'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentStateCard(DeliveryLifecycleState state, DeliveryLifecycleContext lifecycle, bool isSender, bool isCarrier, double total, double base, double reward, double fee, String currency) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(DeliveryLifecycleMapper.getTitle(state), style: ShipdeHopTypography.displayMedium.copyWith(fontSize: 20)),
        const SizedBox(height: 5),
        Text(DeliveryLifecycleMapper.getSubtitle(state), style: ShipdeHopTypography.bodyMedium),
        const SizedBox(height: 16),
        if (isSender && DeliveryLifecycleActionHelper.canPayEscrow(lifecycle)) ...[
          _primaryAction(
            'Accept traveller match (No payment in beta)',
            Icons.check_circle_outline_rounded,
            () async {
              try {
                await _repository.acceptMatch(widget.orderId);
                _loadDetails();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
          ),
          const SizedBox(height: 8),
        ],
        if (isSender && state == DeliveryLifecycleState.paymentSecured) ...[
          _primaryAction('View Pickup Code for Traveller', Icons.pin_outlined, _showPickupCodeModal),
          const SizedBox(height: 8),
        ],
        if (isCarrier && DeliveryLifecycleActionHelper.canStartDelivery(lifecycle)) ...[
          _primaryAction('Enter pickup code · start delivery', Icons.navigation_rounded, _handleStartDelivery),
          const SizedBox(height: 8),
        ],
        if (isSender && DeliveryLifecycleActionHelper.canViewHandoffCode(lifecycle)) ...[
          _primaryAction('View Handoff OTP / QR Code', Icons.qr_code_2_rounded, () => SenderHandoffModal.show(context, widget.orderId, _repository)),
          const SizedBox(height: 8),
        ],
        if (isCarrier && DeliveryLifecycleActionHelper.canVerifyHandoff(lifecycle)) ...[
          _primaryAction('Verify delivery handoff', Icons.verified_user_outlined, () => TravellerHandoffModal.show(context, widget.orderId, _repository, _loadDetails)),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(onPressed: _openChat, icon: const Icon(Icons.chat_bubble_outline_rounded), label: Text(isCarrier ? 'Message sender' : 'Message traveller')),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (state != DeliveryLifecycleState.completed && state != DeliveryLifecycleState.cancelled && state != DeliveryLifecycleState.inTransit) ...[
              Expanded(
                child: TextButton.icon(
                  onPressed: _handleCancelOrder,
                  icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                  label: const Text('Cancel match', style: TextStyle(color: Colors.red, fontSize: 13)),
                ),
              ),
            ],
            Expanded(
              child: TextButton.icon(
                onPressed: _openReportIssue,
                icon: const Icon(Icons.report_problem_outlined, size: 16, color: Colors.orange),
                label: const Text('Report an issue', style: TextStyle(color: Colors.orange, fontSize: 13)),
              ),
            ),
          ],
        ),
      ]),
    );
  }

  Widget _primaryAction(String label, IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, textAlign: TextAlign.center),
        style: ElevatedButton.styleFrom(backgroundColor: ShipdeHopColors.brandPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      ),
    );
  }

  Widget _hopPayCard(double total, double base, double reward, double fee, String currency) {
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.info_outline_rounded, color: Colors.blueGrey.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text('Beta Delivery · Payments Disabled', style: ShipdeHopTypography.titleSmall.copyWith(color: Colors.blueGrey.shade800))),
          ]),
          const SizedBox(height: 8),
          Text(
            'This is a peer-to-peer beta delivery test. No money, escrow, or platform fees are processed through ShipdeHop in this beta release.',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: ShipdeHopColors.successBg, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.shield_rounded, color: ShipdeHopColors.success),
          const SizedBox(width: 8),
          Expanded(child: Text('Protected by HopPay', style: ShipdeHopTypography.titleSmall.copyWith(color: ShipdeHopColors.success))),
          Text(MoneyFormatter.format(total, currency), style: ShipdeHopTypography.moneyCard.copyWith(color: ShipdeHopColors.success)),
        ]),
        const SizedBox(height: 10),
        EscrowBreakdown(base: base, reward: reward, platformFee: fee, currency: currency, showTitle: false),
      ]),
    );
  }

  Widget _historyDisclosure(DeliveryLifecycleContext lifecycle) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: const Text('Journey history', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Previous milestones and payment events', style: TextStyle(fontSize: 12, color: ShipdeHopColors.textMuted)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: DeliveryLifecycleState.values
                  .where((s) => s != DeliveryLifecycleState.cancelled)
                  .map((s) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(s == DeliveryLifecycleMapper.resolveState(lifecycle) ? Icons.radio_button_checked : Icons.check_circle_outline, color: s == DeliveryLifecycleMapper.resolveState(lifecycle) ? ShipdeHopColors.brandPrimary : ShipdeHopColors.textMuted),
                        title: Text(DeliveryLifecycleMapper.getTitle(s), style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: ShipdeHopColors.warning),
          const SizedBox(height: 12),
          Text('Could not load this delivery', style: ShipdeHopTypography.titleMedium),
          const SizedBox(height: 6),
          Text('Your payment and order remain unchanged. Try again.', textAlign: TextAlign.center, style: ShipdeHopTypography.bodyMedium),
          const SizedBox(height: 14),
          ElevatedButton(onPressed: _loadDetails, child: const Text('Retry')),
        ]),
      ),
    );
  }

  String _routeTitle(Map<String, dynamic> order, String orderType) {
    final title = order['title']?.toString();
    if (title?.isNotEmpty == true) return title!;
    final origin = order['origin_name']?.toString() ?? order['originName']?.toString();
    final dest = order['dest_name']?.toString() ?? order['destName']?.toString();
    if (origin?.isNotEmpty == true && dest?.isNotEmpty == true) return '$origin → $dest';
    if (widget.orderId == LiveDeliveryRepository.protectedOrderId) return 'Mumbai → Pune';
    if (orderType == 'RIDE') return 'Your CarPool journey';
    if (orderType == 'MARKETPLACE') return 'Your marketplace delivery';
    return 'Your parcel journey';
  }
}
