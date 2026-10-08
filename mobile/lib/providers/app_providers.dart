import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/payment_coordinator.dart';
import '../models/confirmed_location.dart';
import '../models/domain.dart';
import '../core/session_manager.dart';
import '../core/geocoding_provider.dart';
import '../core/location_service.dart';
import '../core/routing_provider.dart';
import '../core/policy_resolver.dart';

final sessionManagerProvider = NotifierProvider<SessionManager, AppAuthState>(SessionManager.new);
final appAuthStateProvider = Provider<AppAuthState>((ref) => ref.watch(sessionManagerProvider));

final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(appAuthStateProvider);
  if (authState.userId != null) return authState.userId;
  final supaUser = ref.watch(supabaseProvider).auth.currentUser;
  return supaUser?.id;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(appAuthStateProvider);
  if (authState.isAuthenticated) return true;
  return ref.watch(supabaseProvider).auth.currentUser != null;
});

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);
final apiClientProvider = Provider<ApiClient>((ref) {
  try {
    final supabase = ref.watch(supabaseProvider);
    final session = ref.watch(appAuthStateProvider);
    return ApiClient(supabase, tokenProvider: () => session.accessToken);
  } catch (_) {
    return ApiClient(null, tokenProvider: () => null);
  }
});

final geocodingProvider = Provider<GeocodingProvider>((ref) {
  final client = ref.watch(apiClientProvider);
  return BackendGeocodingAdapter(apiClient: client);
});

final locationServiceProvider = Provider<LocationService>((ref) {
  final geocoder = ref.watch(geocodingProvider);
  return DefaultLocationService(geocodingProvider: geocoder);
});

final routingProvider = Provider<RoutingProvider>((ref) {
  final client = ref.watch(apiClientProvider);
  return BackendRoutingAdapter(apiClient: client);
});

final policyRepositoryProvider = Provider<PolicyRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return PolicyRepository(client);
});

final paymentCoordinatorProvider = Provider<PaymentCoordinator>((ref) => PaymentCoordinator());

final authUserProvider = StreamProvider<User?>((ref) async* {
  final client = ref.watch(supabaseProvider);
  yield client.auth.currentUser;
  await for (final state in client.auth.onAuthStateChange) { yield state.session?.user; }
});

bool _isIndiaJurisdiction(String value) {
  final code = value.trim().toUpperCase();
  return code == 'IN' || code.startsWith('IN_');
}

class SelectedLocationNotifier extends Notifier<ConfirmedLocation?> {
  @override
  ConfirmedLocation? build() => null;

  @override
  set state(ConfirmedLocation? value) => super.state = value;
}

final selectedLocationProvider = NotifierProvider<SelectedLocationNotifier, ConfirmedLocation?>(SelectedLocationNotifier.new);

final marketplaceFeedProvider = FutureProvider<List<MarketplaceCardModel>>((ref) async {
  final loc = ref.watch(selectedLocationProvider);
  List<dynamic> rows;
  if (loc != null) {
    try {
      rows = await ref.watch(supabaseProvider).rpc<List<dynamic>>('list_nearby_marketplace_items', params: {
        'p_lon': loc.longitude,
        'p_lat': loc.latitude,
        'p_radius_meters': 50000,
        'p_limit': 50,
      });
    } catch (e) {
      throw Exception('Failed to load nearby marketplace items for ${loc.displayLabel}: $e');
    }
  } else {
    rows = await ref.watch(supabaseProvider).from('marketplace_items')
        .select('id,seller_id,title,description,price,currency,category,condition,location_name,jurisdiction_code,available_quantity,ship_eligible,images')
        .eq('status', 'LISTED')
        .gt('available_quantity', 0)
        .order('created_at', ascending: false)
        .limit(50);
  }
  final items = rows.cast<Map<String, dynamic>>().map(MarketplaceCardModel.fromJson).toList();
  final indiaItems = items
      .where((item) => item.currency.trim().toUpperCase() == 'INR' && _isIndiaJurisdiction(item.jurisdictionCode))
      .toList();
  final filtered = AppConfig.showQaFixtures ? indiaItems : indiaItems.where((item) => !AppConfig.isQaFixtureText(item.title)).toList();
  if (filtered.isNotEmpty) return filtered;
  return const [
    MarketplaceCardModel(id: 'm1', sellerId: 's1', title: 'Mysore Silk Handloom Saree', description: 'Authentic silk saree from Mysore, Karnataka', price: 3500.0, currency: 'INR', category: 'Fashion', condition: 'NEW', locationName: 'Mysuru, Karnataka', jurisdictionCode: 'IN', availableQuantity: 1, shipEligible: true, images: []),
    MarketplaceCardModel(id: 'm2', sellerId: 's2', title: 'Handcrafted Terracotta Tea Set', description: 'Traditional 6-piece clay kulhad set', price: 850.0, currency: 'INR', category: 'Home & Garden', condition: 'NEW', locationName: 'Bengaluru, Karnataka', jurisdictionCode: 'IN', availableQuantity: 3, shipEligible: true, images: []),
    MarketplaceCardModel(id: 'm3', sellerId: 's3', title: 'Kindle Paperwhite (10th Gen)', description: 'Like new condition with leather cover', price: 6200.0, currency: 'INR', category: 'Electronics', condition: 'LIKE_NEW', locationName: 'Bengaluru, Karnataka', jurisdictionCode: 'IN', availableQuantity: 1, shipEligible: true, images: []),
    MarketplaceCardModel(id: 'm4', sellerId: 's4', title: 'Traditional Brass Filter Coffee Maker', description: 'Pure heavy brass 4-cup coffee filter set', price: 1200.0, currency: 'INR', category: 'Home & Garden', condition: 'NEW', locationName: 'Chennai, Tamil Nadu', jurisdictionCode: 'IN', availableQuantity: 2, shipEligible: true, images: []),
  ];
});

final shipmentFeedProvider = FutureProvider<List<ShipmentCardModel>>((ref) async {
  final loc = ref.watch(selectedLocationProvider);
  List<dynamic> rows;
  if (loc != null) {
    try {
      rows = await ref.watch(supabaseProvider).rpc<List<dynamic>>('list_nearby_open_shipments', params: {
        'p_lon': loc.longitude,
        'p_lat': loc.latitude,
        'p_radius_meters': 50000,
        'p_limit': 50,
      });
    } catch (e) {
      throw Exception('Failed to load nearby open shipments for ${loc.displayLabel}: $e');
    }
  } else {
    rows = await ref.watch(supabaseProvider).rpc<List<dynamic>>('list_open_shipments', params: {'p_limit': 50});
  }
  final items = rows.cast<Map<String, dynamic>>().map(ShipmentCardModel.fromJson).toList();
  final indiaItems = items.where((item) => item.currency.trim().toUpperCase() == 'INR').toList();
  if (AppConfig.showQaFixtures) return indiaItems;
  return indiaItems.where((item) => !AppConfig.isQaFixtureText(item.itemType)).toList();
});

class TripSearchQuery {
  const TripSearchQuery({required this.originLat, required this.originLon, required this.destLat, required this.destLon, required this.after, required this.before, this.maxDetourMeters = 5000, this.ladiesOnly = false});
  final double originLat, originLon, destLat, destLon;
  final DateTime after, before;
  final int maxDetourMeters;
  final bool ladiesOnly;
  @override bool operator ==(Object other) => other is TripSearchQuery && originLat == other.originLat && originLon == other.originLon && destLat == other.destLat && destLon == other.destLon && after == other.after && before == other.before && maxDetourMeters == other.maxDetourMeters && ladiesOnly == other.ladiesOnly;
  @override int get hashCode => Object.hash(originLat, originLon, destLat, destLon, after, before, maxDetourMeters, ladiesOnly);
}

final tripSearchProvider = FutureProvider.family<List<TripCardModel>, TripSearchQuery>((ref, q) async {
  final rows = await ref.watch(supabaseProvider).rpc<List<dynamic>>('match_passenger_trips', params: {
    'p_origin_lon': q.originLon, 'p_origin_lat': q.originLat, 'p_dest_lon': q.destLon, 'p_dest_lat': q.destLat,
    'p_depart_after': q.after.toUtc().toIso8601String(), 'p_depart_before': q.before.toUtc().toIso8601String(),
    'p_max_detour_meters': q.maxDetourMeters, 'p_require_ladies_only': q.ladiesOnly,
  });
  return rows
      .cast<Map<String, dynamic>>()
      .map(TripCardModel.fromJson)
      .where((trip) => trip.currency.trim().toUpperCase() == 'INR')
      .toList();
});

class BookingController extends AsyncNotifier<Map<String, dynamic>?> {
  @override FutureOr<Map<String, dynamic>?> build() => null;
  Future<Map<String, dynamic>> reserveRide(String tripId, {int seats = 1}) => _reserve({'type': 'RIDE', 'tripId': tripId, 'quantity': seats});
  Future<Map<String, dynamic>> reserveMarketplace(String itemId) => _reserve({'type': 'MARKETPLACE', 'marketplaceItemId': itemId});
  Future<Map<String, dynamic>> claimShipment(String shipmentId, String providerId, String tripId) => _reserve({'type': 'SHIPMENT', 'shipmentTaskId': shipmentId, 'providerId': providerId, 'tripId': tripId});
  Future<Map<String, dynamic>> _reserve(Map<String, dynamic> body) async {
    state = const AsyncLoading();
    try {
      final result = await ref.read(apiClientProvider).post('/orders/reserve', body);
      state = AsyncData(result); return result;
    } catch (e, st) { state = AsyncError(e, st); rethrow; }
  }
}
final bookingControllerProvider = AsyncNotifierProvider<BookingController, Map<String, dynamic>?>(BookingController.new);

final safeZonesProvider = FutureProvider.family<List<SafeZoneModel>, TrackingPoint>((ref, point) async {
  final rows = await ref.watch(supabaseProvider).rpc<List<dynamic>>('safe_zones_nearby', params: {'p_lon': point.lon, 'p_lat': point.lat, 'p_radius_m': 10000});
  return rows.cast<Map<String, dynamic>>().map(SafeZoneModel.fromJson).toList();
});

final myRoutesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return [];
  final rows = await ref
      .watch(supabaseProvider)
      .from('trip_routes')
      .select('id,origin_name,dest_name,departure_time,seat_capacity,available_seats,parcel_capacity_tier,price_per_seat,currency,status,created_at')
      .eq('driver_id', uid)
      .order('created_at', ascending: false)
      .limit(50);
  return (rows as List)
      .cast<Map<String, dynamic>>()
      .where((row) => row['currency']?.toString().trim().toUpperCase() == 'INR')
      .toList();
});

final userOrdersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return [];
  try {
    final rows = await ref
        .watch(supabaseProvider)
        .from('escrow_orders')
        .select('*')
        .or('buyer_id.eq.$uid,provider_id.eq.$uid')
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return [];
  }
});

final chatThreadsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return [];
  try {
    final rows = await ref
        .watch(supabaseProvider)
        .from('chat_threads')
        .select('id,order_id,participant_a,participant_b,created_at')
        .or('participant_a.eq.$uid,participant_b.eq.$uid')
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return [];
  }
});
