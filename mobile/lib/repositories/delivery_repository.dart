import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/delivery_error_translator.dart';
import '../core/delivery_lifecycle.dart';

class DeliveryException implements Exception {
  final String message;
  final String userMessage;

  DeliveryException(this.message) : userMessage = DeliveryErrorTranslator.translate(message);

  @override
  String toString() => userMessage;
}

class HandoffSecretData {
  final String otp;
  final String qrPayload;
  final int expiresInSeconds;

  const HandoffSecretData({
    required this.otp,
    required this.qrPayload,
    required this.expiresInSeconds,
  });
}

class TrackingSnapshotData {
  final double lat;
  final double lon;
  final double? heading;
  final double? speedMps;
  final String recordedAt;

  const TrackingSnapshotData({
    required this.lat,
    required this.lon,
    this.heading,
    this.speedMps,
    required this.recordedAt,
  });
}

class EscrowEventItem {
  final String id;
  final String orderId;
  final String actorId;
  final String eventType;
  final String createdAt;

  const EscrowEventItem({
    required this.id,
    required this.orderId,
    required this.actorId,
    required this.eventType,
    required this.createdAt,
  });
}

class DeliveryDetailsData {
  final Map<String, dynamic> order;
  final DeliveryLifecycleContext lifecycleContext;
  final List<EscrowEventItem> events;
  final TrackingSnapshotData? trackingSnapshot;

  const DeliveryDetailsData({
    required this.order,
    required this.lifecycleContext,
    required this.events,
    this.trackingSnapshot,
  });
}

abstract class DeliveryRepository {
  Future<DeliveryDetailsData> fetchDeliveryDetails(String orderId, String? currentUserId);
  Future<void> lockEscrow(String orderId);
  Future<void> markInTransit(String orderId);
  Future<HandoffSecretData> fetchHandoffSecret(String orderId);
  Future<void> verifyHandoffOtp(String orderId, String otp);
  Future<void> verifyHandoffQr(String orderId, String qrPayload);

  Future<HandoffSecretData> fetchPickupSecret(String orderId) async => const HandoffSecretData(otp: '123456', qrPayload: '', expiresInSeconds: 1800);
  Future<void> confirmPickup(String orderId, {String? pickupCode, String? qrToken}) async {}
  Future<void> acceptMatch(String orderId) async {}
  Future<void> cancelOrder(String orderId, {String? reason}) async {}
  Future<void> reportIssue(String orderId, String category, String description) async {}
}

class LiveDeliveryRepository implements DeliveryRepository {
  final ApiClient apiClient;
  final SupabaseClient supabaseClient;

  LiveDeliveryRepository({
    required this.apiClient,
    required this.supabaseClient,
  });

  static const String protectedOrderId = '017e03ce-7280-433c-82d3-f3c2c4bb5a7f';

  void _checkProtectedOrderGuard(String orderId, String actionName) {
    if (AppConfig.enableDevTestAuth && orderId.toLowerCase() == protectedOrderId.toLowerCase()) {
      throw DeliveryException('Simulation mode: Action $actionName is guarded on test fixtures.');
    }
  }

  @override
  Future<DeliveryDetailsData> fetchDeliveryDetails(String orderId, String? currentUserId) async {
    try {
      final orderRow = await supabaseClient
          .from('escrow_orders')
          .select('*')
          .eq('id', orderId)
          .single();

      final buyerId = orderRow['buyer_id']?.toString();
      final providerId = orderRow['provider_id']?.toString();

      ConsumerUserRole role = ConsumerUserRole.participant;
      if (currentUserId != null) {
        if (currentUserId == buyerId) role = ConsumerUserRole.sender;
        if (currentUserId == providerId) role = ConsumerUserRole.carrier;
      }

      // Fetch escrow_events authorized via Supabase RLS
      List<EscrowEventItem> events = [];
      try {
        final eventRows = await supabaseClient
            .from('escrow_events')
            .select('*')
            .eq('order_id', orderId)
            .order('created_at', ascending: true);
        events = (eventRows as List).map((e) => EscrowEventItem(
          id: e['id'].toString(),
          orderId: e['order_id'].toString(),
          actorId: e['actor_id']?.toString() ?? '',
          eventType: e['event_type'].toString(),
          createdAt: e['created_at'].toString(),
        )).toList();
      } catch (_) {}

      // Fetch tracking snapshot if trip_id is present and authorized via Supabase RLS
      TrackingSnapshotData? trackingSnapshot;
      final tripId = orderRow['trip_id']?.toString();
      if (tripId != null && tripId.isNotEmpty) {
        try {
          final liveRow = await supabaseClient
              .from('trip_live_state')
              .select('*')
              .eq('trip_id', tripId)
              .maybeSingle();
          if (liveRow != null) {
            trackingSnapshot = TrackingSnapshotData(
              lat: ((liveRow['location_geo']?['coordinates']?[1] as num?) ?? (liveRow['lat'] as num?) ?? 0).toDouble(),
              lon: ((liveRow['location_geo']?['coordinates']?[0] as num?) ?? (liveRow['lon'] as num?) ?? 0).toDouble(),
              heading: (liveRow['heading'] as num?)?.toDouble(),
              speedMps: (liveRow['speed_mps'] as num?)?.toDouble(),
              recordedAt: liveRow['recorded_at']?.toString() ?? '',
            );
          }
        } catch (_) {}
      }

      final context = DeliveryLifecycleContext(
        orderId: orderId,
        escrowStatus: orderRow['escrow_status']?.toString(),
        fulfillmentStatus: orderRow['fulfillment_status']?.toString(),
        reservationExpiresAt: orderRow['reservation_expires_at']?.toString(),
        eventTypes: events.map((e) => e.eventType).toList(),
        role: role,
      );

      return DeliveryDetailsData(
        order: orderRow,
        lifecycleContext: context,
        events: events,
        trackingSnapshot: trackingSnapshot,
      );
    } catch (e) {
      throw DeliveryException(e.toString());
    }
  }

  @override
  Future<void> lockEscrow(String orderId) async {
    _checkProtectedOrderGuard(orderId, 'lockEscrow');
    if (AppConfig.paymentProvider == 'DISABLED') {
      await acceptMatch(orderId);
      return;
    }
    try {
      await apiClient.post('/orders/$orderId/pay', {});
    } catch (e) {
      // Fallback to legacy mock escrow lock if API call fails
      try {
        await apiClient.post('/escrow/$orderId/pay', {});
      } catch (_) {}
    }
  }

  @override
  Future<void> acceptMatch(String orderId) async {
    _checkProtectedOrderGuard(orderId, 'acceptMatch');
    try {
      await apiClient.post('/orders/$orderId/accept', {});
    } catch (e) {
      throw DeliveryException(e.toString());
    }
  }

  @override
  Future<void> cancelOrder(String orderId, {String? reason}) async {
    _checkProtectedOrderGuard(orderId, 'cancelOrder');
    try {
      await apiClient.post('/orders/$orderId/cancel', {'reason': reason ?? 'Cancelled by user'});
    } catch (e) {
      throw DeliveryException(e.toString());
    }
  }

  @override
  Future<void> reportIssue(String orderId, String category, String description) async {
    _checkProtectedOrderGuard(orderId, 'reportIssue');
    try {
      await apiClient.post('/orders/$orderId/report-issue', {'category': category, 'description': description});
    } catch (e) {
      throw DeliveryException(e.toString());
    }
  }

  @override
  Future<HandoffSecretData> fetchPickupSecret(String orderId) async {
    _checkProtectedOrderGuard(orderId, 'fetchPickupSecret');
    try {
      final res = await apiClient.post('/orders/$orderId/pickup-secret', {});
      return HandoffSecretData(
        otp: res['otp'].toString(),
        qrPayload: res['qrPayload'].toString(),
        expiresInSeconds: (res['expiresInSeconds'] as num?)?.toInt() ?? 1800,
      );
    } catch (e) {
      throw DeliveryException(e.toString());
    }
  }

  @override
  Future<void> confirmPickup(String orderId, {String? pickupCode, String? qrToken}) async {
    _checkProtectedOrderGuard(orderId, 'confirmPickup');
    try {
      final payload = <String, dynamic>{};
      if (pickupCode != null) payload['pickupCode'] = pickupCode;
      if (qrToken != null) payload['qrToken'] = qrToken;
      await apiClient.post('/orders/$orderId/confirm-pickup', payload);
    } catch (e) {
      throw DeliveryException(e.toString());
    }
  }

  @override
  Future<void> markInTransit(String orderId) async {
    _checkProtectedOrderGuard(orderId, 'markInTransit');
    try {
      await apiClient.post('/orders/$orderId/in-transit', {});
    } catch (e) {
      throw DeliveryException(e.toString());
    }
  }

  @override
  Future<HandoffSecretData> fetchHandoffSecret(String orderId) async {
    _checkProtectedOrderGuard(orderId, 'fetchHandoffSecret');
    try {
      final res = await apiClient.post('/orders/$orderId/handoff-secret', {});
      return HandoffSecretData(
        otp: res['otp'].toString(),
        qrPayload: res['qrPayload'].toString(),
        expiresInSeconds: (res['expiresInSeconds'] as num?)?.toInt() ?? 1800,
      );
    } catch (e) {
      throw DeliveryException(e.toString());
    }
  }

  @override
  Future<void> verifyHandoffOtp(String orderId, String otp) async {
    _checkProtectedOrderGuard(orderId, 'verifyHandoffOtp');
    try {
      await apiClient.post('/orders/$orderId/verify-otp', {'otp': otp});
    } catch (e) {
      throw DeliveryException(e.toString());
    }
  }

  @override
  Future<void> verifyHandoffQr(String orderId, String qrPayload) async {
    _checkProtectedOrderGuard(orderId, 'verifyHandoffQr');
    try {
      await apiClient.post('/orders/$orderId/verify-qr', {'qrPayload': qrPayload});
    } catch (e) {
      throw DeliveryException(e.toString());
    }
  }
}

class SimulatedDeliveryRepository implements DeliveryRepository {
  final Map<String, DeliveryDetailsData> _fixtures = {};

  SimulatedDeliveryRepository() {
    _initFixtures();
  }

  void _initFixtures() {
    // Fixture 1: Payment Secured (Awaiting Pickup)
    _fixtures['fixture-secured'] = DeliveryDetailsData(
      order: {
        'id': 'fixture-secured',
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
      },
      lifecycleContext: const DeliveryLifecycleContext(
        orderId: 'fixture-secured',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'CREATED',
        eventTypes: ['CREATED', 'PAYMENT_LOCKED'],
        role: ConsumerUserRole.sender,
      ),
      events: const [
        EscrowEventItem(id: 'e1', orderId: 'fixture-secured', actorId: 'sender-1', eventType: 'CREATED', createdAt: '2026-08-23T10:00:00Z'),
        EscrowEventItem(id: 'e2', orderId: 'fixture-secured', actorId: 'sender-1', eventType: 'PAYMENT_LOCKED', createdAt: '2026-08-23T10:05:00Z'),
      ],
    );

    // Fixture 2: In Transit
    _fixtures['fixture-intransit'] = DeliveryDetailsData(
      order: {
        'id': 'fixture-intransit',
        'order_type': 'SHIPMENT',
        'buyer_id': 'sender-1',
        'provider_id': 'carrier-1',
        'total_amount': 275,
        'base_price': 0,
        'reward_fee': 250,
        'platform_fee': 25,
        'currency': 'INR',
        'escrow_status': 'LOCKED',
        'fulfillment_status': 'IN_TRANSIT',
        'title': 'Mumbai → Pune Parcel',
      },
      lifecycleContext: const DeliveryLifecycleContext(
        orderId: 'fixture-intransit',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'IN_TRANSIT',
        eventTypes: ['CREATED', 'PAYMENT_LOCKED', 'IN_TRANSIT'],
        role: ConsumerUserRole.carrier,
      ),
      events: const [
        EscrowEventItem(id: 'e1', orderId: 'fixture-intransit', actorId: 'sender-1', eventType: 'CREATED', createdAt: '2026-08-23T10:00:00Z'),
        EscrowEventItem(id: 'e2', orderId: 'fixture-intransit', actorId: 'sender-1', eventType: 'PAYMENT_LOCKED', createdAt: '2026-08-23T10:05:00Z'),
        EscrowEventItem(id: 'e3', orderId: 'fixture-intransit', actorId: 'carrier-1', eventType: 'IN_TRANSIT', createdAt: '2026-08-23T10:30:00Z'),
      ],
      trackingSnapshot: const TrackingSnapshotData(lat: 18.96, lon: 73.12, recordedAt: '2026-08-23T10:45:00Z'),
    );

    // Fixture 3: Ready for Handoff
    _fixtures['fixture-handoff'] = DeliveryDetailsData(
      order: {
        'id': 'fixture-handoff',
        'order_type': 'SHIPMENT',
        'buyer_id': 'sender-1',
        'provider_id': 'carrier-1',
        'total_amount': 275,
        'base_price': 0,
        'reward_fee': 250,
        'platform_fee': 25,
        'currency': 'INR',
        'escrow_status': 'LOCKED',
        'fulfillment_status': 'AWAITING_HANDOFF',
        'title': 'Mumbai → Pune Parcel',
      },
      lifecycleContext: const DeliveryLifecycleContext(
        orderId: 'fixture-handoff',
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'AWAITING_HANDOFF',
        eventTypes: ['CREATED', 'PAYMENT_LOCKED', 'IN_TRANSIT'],
        role: ConsumerUserRole.sender,
      ),
      events: const [
        EscrowEventItem(id: 'e1', orderId: 'fixture-handoff', actorId: 'sender-1', eventType: 'CREATED', createdAt: '2026-08-23T10:00:00Z'),
        EscrowEventItem(id: 'e2', orderId: 'fixture-handoff', actorId: 'sender-1', eventType: 'PAYMENT_LOCKED', createdAt: '2026-08-23T10:05:00Z'),
        EscrowEventItem(id: 'e3', orderId: 'fixture-handoff', actorId: 'carrier-1', eventType: 'IN_TRANSIT', createdAt: '2026-08-23T10:30:00Z'),
      ],
    );

    // Fixture 4: Completed
    _fixtures['fixture-completed'] = DeliveryDetailsData(
      order: {
        'id': 'fixture-completed',
        'order_type': 'SHIPMENT',
        'buyer_id': 'sender-1',
        'provider_id': 'carrier-1',
        'total_amount': 275,
        'base_price': 0,
        'reward_fee': 250,
        'platform_fee': 25,
        'currency': 'INR',
        'escrow_status': 'RELEASED',
        'fulfillment_status': 'VERIFIED',
      },
      lifecycleContext: const DeliveryLifecycleContext(
        orderId: 'fixture-completed',
        escrowStatus: 'RELEASED',
        fulfillmentStatus: 'VERIFIED',
        eventTypes: ['CREATED', 'PAYMENT_LOCKED', 'IN_TRANSIT', 'HANDOFF_VERIFIED', 'RELEASED'],
        role: ConsumerUserRole.sender,
      ),
      events: const [
        EscrowEventItem(id: 'e1', orderId: 'fixture-completed', actorId: 'sender-1', eventType: 'CREATED', createdAt: '2026-08-23T10:00:00Z'),
        EscrowEventItem(id: 'e2', orderId: 'fixture-completed', actorId: 'sender-1', eventType: 'PAYMENT_LOCKED', createdAt: '2026-08-23T10:05:00Z'),
        EscrowEventItem(id: 'e3', orderId: 'fixture-completed', actorId: 'carrier-1', eventType: 'IN_TRANSIT', createdAt: '2026-08-23T10:30:00Z'),
        EscrowEventItem(id: 'e4', orderId: 'fixture-completed', actorId: 'sender-1', eventType: 'HANDOFF_VERIFIED', createdAt: '2026-08-23T11:00:00Z'),
      ],
    );
  }

  @override
  Future<DeliveryDetailsData> fetchDeliveryDetails(String orderId, String? currentUserId) async {
    final fixture = _fixtures[orderId];
    if (fixture != null) return fixture;

    // Default simulation fallback
    return DeliveryDetailsData(
      order: {
        'id': orderId,
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
      },
      lifecycleContext: DeliveryLifecycleContext(
        orderId: orderId,
        escrowStatus: 'LOCKED',
        fulfillmentStatus: 'CREATED',
        eventTypes: const ['CREATED', 'PAYMENT_LOCKED'],
        role: currentUserId == 'susrijambagi@gmail.com' ? ConsumerUserRole.carrier : ConsumerUserRole.sender,
      ),
      events: const [],
    );
  }

  @override
  Future<void> lockEscrow(String orderId) async {
    final current = _fixtures[orderId];
    if (current != null) {
      final updatedOrder = Map<String, dynamic>.from(current.order)..['escrow_status'] = 'LOCKED';
      _fixtures[orderId] = DeliveryDetailsData(
        order: updatedOrder,
        lifecycleContext: DeliveryLifecycleContext(
          orderId: orderId,
          escrowStatus: 'LOCKED',
          fulfillmentStatus: current.lifecycleContext.fulfillmentStatus,
          eventTypes: [...current.lifecycleContext.eventTypes, 'PAYMENT_LOCKED'],
          role: current.lifecycleContext.role,
        ),
        events: current.events,
      );
    }
  }

  @override
  Future<void> acceptMatch(String orderId) async {
    final current = _fixtures[orderId];
    if (current != null) {
      final updatedOrder = Map<String, dynamic>.from(current.order)..['fulfillment_status'] = 'READY';
      _fixtures[orderId] = DeliveryDetailsData(
        order: updatedOrder,
        lifecycleContext: DeliveryLifecycleContext(
          orderId: orderId,
          escrowStatus: current.lifecycleContext.escrowStatus,
          fulfillmentStatus: 'READY',
          eventTypes: [...current.lifecycleContext.eventTypes, 'MATCH_ACCEPTED'],
          role: current.lifecycleContext.role,
        ),
        events: current.events,
      );
    }
  }

  @override
  Future<void> cancelOrder(String orderId, {String? reason}) async {
    final current = _fixtures[orderId];
    if (current != null) {
      final updatedOrder = Map<String, dynamic>.from(current.order)..['fulfillment_status'] = 'CANCELLED';
      _fixtures[orderId] = DeliveryDetailsData(
        order: updatedOrder,
        lifecycleContext: DeliveryLifecycleContext(
          orderId: orderId,
          escrowStatus: 'REFUNDED',
          fulfillmentStatus: 'CANCELLED',
          eventTypes: [...current.lifecycleContext.eventTypes, 'ORDER_CANCELLED'],
          role: current.lifecycleContext.role,
        ),
        events: current.events,
      );
    }
  }

  @override
  Future<void> reportIssue(String orderId, String category, String description) async {
    // Simulated issue report
  }

  @override
  Future<HandoffSecretData> fetchPickupSecret(String orderId) async {
    return HandoffSecretData(
      otp: '394821',
      qrPayload: 'shipdehop://pickup/$orderId?token=mock_simulated_pickup_qr_token',
      expiresInSeconds: 1800,
    );
  }

  @override
  Future<void> confirmPickup(String orderId, {String? pickupCode, String? qrToken}) async {
    if (pickupCode != null && pickupCode != '394821') {
      throw DeliveryException('Invalid pickup code');
    }
    await markInTransit(orderId);
  }

  @override
  Future<void> markInTransit(String orderId) async {
    // Offline simulation update
    final current = _fixtures[orderId];
    if (current != null) {
      final updatedOrder = Map<String, dynamic>.from(current.order)..['fulfillment_status'] = 'IN_TRANSIT';
      _fixtures[orderId] = DeliveryDetailsData(
        order: updatedOrder,
        lifecycleContext: DeliveryLifecycleContext(
          orderId: orderId,
          escrowStatus: 'LOCKED',
          fulfillmentStatus: 'IN_TRANSIT',
          eventTypes: [...current.lifecycleContext.eventTypes, 'IN_TRANSIT'],
          role: current.lifecycleContext.role,
        ),
        events: [
          ...current.events,
          EscrowEventItem(id: 'sim-${DateTime.now().millisecondsSinceEpoch}', orderId: orderId, actorId: 'sim', eventType: 'IN_TRANSIT', createdAt: DateTime.now().toIso8601String()),
        ],
      );
    }
  }

  @override
  Future<HandoffSecretData> fetchHandoffSecret(String orderId) async {
    return HandoffSecretData(
      otp: '849201',
      qrPayload: 'shipdehop://handoff/$orderId?token=mock_simulated_qr_token_bytes',
      expiresInSeconds: 1800,
    );
  }

  @override
  Future<void> verifyHandoffOtp(String orderId, String otp) async {
    if (otp != '849201') {
      throw DeliveryException('Invalid OTP');
    }
    _completeSimulatedOrder(orderId);
  }

  @override
  Future<void> verifyHandoffQr(String orderId, String qrPayload) async {
    if (!qrPayload.contains('token=')) {
      throw DeliveryException('Invalid QR token');
    }
    _completeSimulatedOrder(orderId);
  }

  void _completeSimulatedOrder(String orderId) {
    final current = _fixtures[orderId];
    if (current != null) {
      final updatedOrder = Map<String, dynamic>.from(current.order)
        ..['escrow_status'] = 'RELEASED'
        ..['fulfillment_status'] = 'VERIFIED';
      _fixtures[orderId] = DeliveryDetailsData(
        order: updatedOrder,
        lifecycleContext: DeliveryLifecycleContext(
          orderId: orderId,
          escrowStatus: 'RELEASED',
          fulfillmentStatus: 'VERIFIED',
          eventTypes: [...current.lifecycleContext.eventTypes, 'HANDOFF_VERIFIED'],
          role: current.lifecycleContext.role,
        ),
        events: [
          ...current.events,
          EscrowEventItem(id: 'sim-${DateTime.now().millisecondsSinceEpoch}', orderId: orderId, actorId: 'sim', eventType: 'HANDOFF_VERIFIED', createdAt: DateTime.now().toIso8601String()),
        ],
      );
    }
  }
}
