import 'package:flutter/material.dart';
import '../core/delivery_lifecycle.dart';
import '../repositories/delivery_repository.dart';
import 'delivery_details_screen.dart';

class LifecycleSimulatorScreen extends StatefulWidget {
  const LifecycleSimulatorScreen({super.key});

  @override
  State<LifecycleSimulatorScreen> createState() => _LifecycleSimulatorScreenState();
}

class _LifecycleSimulatorScreenState extends State<LifecycleSimulatorScreen> {
  ConsumerUserRole _selectedRole = ConsumerUserRole.sender;
  String _selectedStateKey = 'secured';

  late SimulatedDeliveryRepository _simulatedRepository;

  @override
  void initState() {
    super.initState();
    _simulatedRepository = SimulatedDeliveryRepository();
  }

  String get _activeOrderId {
    switch (_selectedStateKey) {
      case 'secured':
        return 'fixture-secured';
      case 'intransit':
        return 'fixture-intransit';
      case 'handoff':
        return 'fixture-handoff';
      case 'completed':
        return 'fixture-completed';
      default:
        return 'fixture-secured';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.science, color: Colors.amber),
            SizedBox(width: 8),
            Text('Dev Lifecycle Simulator'),
          ],
        ),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // SIMULATION CONTROLS BAR
          Container(
            color: Colors.indigo.shade50,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.developer_mode, size: 16, color: Colors.indigo),
                    SizedBox(width: 6),
                    Text(
                      'DEV SIMULATION ONLY • NO BACKEND WRITES',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ROLE SELECTOR
                const Text('User Role:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ChoiceChip(
                      avatar: const Icon(Icons.person, size: 16),
                      label: const Text('Sender / Buyer'),
                      selected: _selectedRole == ConsumerUserRole.sender,
                      onSelected: (val) {
                        if (val) setState(() => _selectedRole = ConsumerUserRole.sender);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: const Icon(Icons.directions_car, size: 16),
                      label: const Text('Traveller / Carrier'),
                      selected: _selectedRole == ConsumerUserRole.carrier,
                      onSelected: (val) {
                        if (val) setState(() => _selectedRole = ConsumerUserRole.carrier);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // STATE SELECTOR
                const Text('Lifecycle State:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('1. Payment Secured'),
                      selected: _selectedStateKey == 'secured',
                      onSelected: (val) {
                        if (val) setState(() => _selectedStateKey = 'secured');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('2. In Transit'),
                      selected: _selectedStateKey == 'intransit',
                      onSelected: (val) {
                        if (val) setState(() => _selectedStateKey = 'intransit');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('3. Ready for Handoff (Synthetic)'),
                      selected: _selectedStateKey == 'handoff',
                      onSelected: (val) {
                        if (val) setState(() => _selectedStateKey = 'handoff');
                      },
                    ),
                    ChoiceChip(
                      label: const Text('4. Completed'),
                      selected: _selectedStateKey == 'completed',
                      onSelected: (val) {
                        if (val) setState(() => _selectedStateKey = 'completed');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // EMBEDDED DELIVERY DETAILS SCREEN PREVIEW
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('sim-${_selectedRole.name}-$_selectedStateKey'),
              child: DeliveryDetailsScreen(
                orderId: _activeOrderId,
                repository: _ConfiguredSimulatedRepository(
                  delegate: _simulatedRepository,
                  role: _selectedRole,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfiguredSimulatedRepository implements DeliveryRepository {
  final SimulatedDeliveryRepository delegate;
  final ConsumerUserRole role;

  _ConfiguredSimulatedRepository({
    required this.delegate,
    required this.role,
  });

  @override
  Future<DeliveryDetailsData> fetchDeliveryDetails(String orderId, String? currentUserId) async {
    final baseData = await delegate.fetchDeliveryDetails(orderId, currentUserId);
    final context = DeliveryLifecycleContext(
      orderId: baseData.lifecycleContext.orderId,
      shipmentStatus: baseData.lifecycleContext.shipmentStatus,
      escrowStatus: baseData.lifecycleContext.escrowStatus,
      fulfillmentStatus: baseData.lifecycleContext.fulfillmentStatus,
      reservationExpiresAt: baseData.lifecycleContext.reservationExpiresAt,
      eventTypes: baseData.lifecycleContext.eventTypes,
      role: role,
    );

    return DeliveryDetailsData(
      order: baseData.order,
      lifecycleContext: context,
      events: baseData.events,
      trackingSnapshot: baseData.trackingSnapshot,
    );
  }

  @override
  Future<void> lockEscrow(String orderId) => delegate.lockEscrow(orderId);

  @override
  Future<void> markInTransit(String orderId) => delegate.markInTransit(orderId);

  @override
  Future<HandoffSecretData> fetchHandoffSecret(String orderId) => delegate.fetchHandoffSecret(orderId);

  @override
  Future<void> verifyHandoffOtp(String orderId, String otp) => delegate.verifyHandoffOtp(orderId, otp);

  @override
  Future<void> verifyHandoffQr(String orderId, String qrPayload) => delegate.verifyHandoffQr(orderId, qrPayload);

  @override
  Future<HandoffSecretData> fetchPickupSecret(String orderId) => delegate.fetchPickupSecret(orderId);

  @override
  Future<void> confirmPickup(String orderId, {String? pickupCode, String? qrToken}) => delegate.confirmPickup(orderId, pickupCode: pickupCode, qrToken: qrToken);

  @override
  Future<void> acceptMatch(String orderId) => delegate.acceptMatch(orderId);

  @override
  Future<void> cancelOrder(String orderId, {String? reason}) => delegate.cancelOrder(orderId, reason: reason);

  @override
  Future<void> reportIssue(String orderId, String category, String description) => delegate.reportIssue(orderId, category, description);
}
