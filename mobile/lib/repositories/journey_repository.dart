import '../core/api_client.dart';
import '../models/confirmed_location.dart';
import '../models/date_flexibility.dart';
import '../models/journey.dart';
import '../models/journey_opportunity.dart';

abstract class JourneyRepository {
  Future<List<Journey>> fetchUserJourneys();
  Future<Journey> fetchJourneyDetails(String journeyId);
  Future<List<JourneyOpportunity>> fetchJourneyOpportunities(String journeyId);
  Future<Journey> createJourney(Journey journey);
}

class LiveJourneyRepository implements JourneyRepository {
  final ApiClient apiClient;

  LiveJourneyRepository({required this.apiClient});

  @override
  Future<List<Journey>> fetchUserJourneys() async {
    final response = await apiClient.get('/trips/user');
    final list = response as List<dynamic>? ?? [];
    return list.map((json) => Journey.fromJson(json as Map<String, dynamic>)).toList();
  }

  @override
  Future<Journey> fetchJourneyDetails(String journeyId) async {
    final response = await apiClient.get('/trips/$journeyId');
    return Journey.fromJson(response as Map<String, dynamic>);
  }

  @override
  Future<List<JourneyOpportunity>> fetchJourneyOpportunities(String journeyId) async {
    final opportunities = <JourneyOpportunity>[];
    final now = DateTime.now();

    try {
      final response = await apiClient.get('/trips/$journeyId/shipment-matches');
      final list = response as List<dynamic>? ?? [];
      for (final json in list) {
        final m = json as Map<String, dynamic>;
        final pickupM = (m['pickupDistanceMeters'] as num?)?.toDouble() ?? (m['pickup_distance_m'] as num?)?.toDouble() ?? 0.0;
        final dropM = (m['dropDistanceMeters'] as num?)?.toDouble() ?? (m['drop_distance_m'] as num?)?.toDouble() ?? 0.0;
        final itemType = m['itemType']?.toString() ?? m['item_type']?.toString();
        final isShopping = itemType == 'URL_PURCHASE';

        final id = m['shipmentTaskId']?.toString() ?? m['id']?.toString() ?? m['shipment_task_id']?.toString();
        if (id == null || id.isEmpty) continue;

        opportunities.add(
          JourneyOpportunity(
            id: id,
            type: isShopping
                ? JourneyOpportunityType.shoppingRequest
                : JourneyOpportunityType.parcel,
            source: isShopping
                ? JourneyOpportunitySource.liveShopping
                : JourneyOpportunitySource.liveParcel,
            origin: ConfirmedLocation(
              displayLabel: m['pickupName']?.toString() ?? m['pickup_name']?.toString() ?? 'Origin',
              formattedAddress: m['pickupName']?.toString() ?? m['pickup_name']?.toString() ?? 'Origin, India',
              latitude: (m['pickupLat'] as num?)?.toDouble() ?? (m['pickup_lat'] as num?)?.toDouble() ?? 0.0,
              longitude: (m['pickupLon'] as num?)?.toDouble() ?? (m['pickup_lon'] as num?)?.toDouble() ?? 0.0,
              countryCode: 'IN',
              countryName: 'India',
            ),
            destination: ConfirmedLocation(
              displayLabel: m['dropName']?.toString() ?? m['drop_name']?.toString() ?? 'Destination',
              formattedAddress: m['dropName']?.toString() ?? m['drop_name']?.toString() ?? 'Destination, India',
              latitude: (m['dropLat'] as num?)?.toDouble() ?? (m['drop_lat'] as num?)?.toDouble() ?? 0.0,
              longitude: (m['dropLon'] as num?)?.toDouble() ?? (m['drop_lon'] as num?)?.toDouble() ?? 0.0,
              countryCode: 'IN',
              countryName: 'India',
            ),
            timing: DateFlexibility(
              earliestDateTime: now,
              latestDateTime: now.add(const Duration(hours: 4)),
            ),
            rewardAmount: (m['rewardAmount'] as num?)?.toDouble() ?? (m['reward_amount'] as num?)?.toDouble() ?? 0.0,
            currency: m['currency']?.toString() ?? 'INR',
            weightKg: (m['weightKg'] as num?)?.toDouble() ?? (m['weight_kg'] as num?)?.toDouble(),
            requesterName: m['senderName']?.toString() ?? m['sender_name']?.toString() ?? 'Verified Sender',
            pickupDistanceMeters: pickupM,
            dropDistanceMeters: dropM,
            matchScore: JourneyOpportunity.calculateScore(pickupM, dropM),
          ),
        );
      }
    } catch (_) {}

    try {
      final response = await apiClient.get('/trips/$journeyId/ride-request-matches');
      final list = response as List<dynamic>? ?? [];
      for (final json in list) {
        final m = json as Map<String, dynamic>;
        final pickupM = (m['pickupDistanceMeters'] as num?)?.toDouble() ?? (m['pickup_distance_m'] as num?)?.toDouble() ?? 0.0;
        final dropM = (m['dropDistanceMeters'] as num?)?.toDouble() ?? (m['drop_distance_m'] as num?)?.toDouble() ?? 0.0;
        final earliestStr = m['earliestDeparture']?.toString() ?? m['earliest_departure']?.toString() ?? '';
        final latestStr = m['latestDeparture']?.toString() ?? m['latest_departure']?.toString() ?? '';
        final earliest = DateTime.tryParse(earliestStr) ?? now;
        final latest = DateTime.tryParse(latestStr) ?? now.add(const Duration(hours: 4));

        final id = m['requestId']?.toString() ?? m['id']?.toString() ?? m['request_id']?.toString();
        if (id == null || id.isEmpty) continue;

        opportunities.add(
          JourneyOpportunity(
            id: id,
            type: JourneyOpportunityType.passenger,
            source: JourneyOpportunitySource.livePassenger,
            origin: ConfirmedLocation(
              displayLabel: m['pickupName']?.toString() ?? m['pickup_name']?.toString() ?? 'Pickup Location',
              formattedAddress: m['pickupName']?.toString() ?? m['pickup_name']?.toString() ?? 'Pickup, India',
              latitude: (m['pickupLat'] as num?)?.toDouble() ?? (m['pickup_lat'] as num?)?.toDouble() ?? 0.0,
              longitude: (m['pickupLon'] as num?)?.toDouble() ?? (m['pickup_lon'] as num?)?.toDouble() ?? 0.0,
              countryCode: 'IN',
              countryName: 'India',
            ),
            destination: ConfirmedLocation(
              displayLabel: m['dropName']?.toString() ?? m['drop_name']?.toString() ?? 'Drop Location',
              formattedAddress: m['dropName']?.toString() ?? m['drop_name']?.toString() ?? 'Drop, India',
              latitude: (m['dropLat'] as num?)?.toDouble() ?? (m['drop_lat'] as num?)?.toDouble() ?? 0.0,
              longitude: (m['dropLon'] as num?)?.toDouble() ?? (m['drop_lon'] as num?)?.toDouble() ?? 0.0,
              countryCode: 'IN',
              countryName: 'India',
            ),
            timing: DateFlexibility(
              earliestDateTime: earliest,
              latestDateTime: latest,
            ),
            rewardAmount: (m['offeredContributionPerSeat'] as num?)?.toDouble() ?? (m['contributionAmount'] as num?)?.toDouble() ?? (m['price_per_seat'] as num?)?.toDouble() ?? (m['reward_amount'] as num?)?.toDouble() ?? 0.0,
            currency: m['currency']?.toString() ?? 'INR',
            seatsNeeded: (m['seatsNeeded'] as num?)?.toInt() ?? (m['seats_needed'] as num?)?.toInt() ?? 1,
            requesterName: m['requesterName']?.toString() ?? m['requester_name']?.toString() ?? 'Verified Passenger',
            pickupDistanceMeters: pickupM,
            dropDistanceMeters: dropM,
            matchScore: JourneyOpportunity.calculateScore(pickupM, dropM),
          ),
        );
      }
    } catch (_) {}

    return opportunities;
  }

  @override
  Future<Journey> createJourney(Journey journey) async {
    if (journey.estimatedTripCost <= 0.0) {
      throw ArgumentError('estimatedTripCost must be positive when creating a journey');
    }
    final payload = {
      'originName': journey.origin.displayLabel,
      'origin': {'lat': journey.origin.latitude, 'lon': journey.origin.longitude},
      'destinationName': journey.destination.displayLabel,
      'destination': {'lat': journey.destination.latitude, 'lon': journey.destination.longitude},
      'departureTime': journey.timing.earliestDateTime.toUtc().toIso8601String(),
      'seats': journey.acceptsPassengers ? journey.seatCapacity : 0,
      'parcelCapacityTier': journey.parcelCapacityTier,
      'pricePerSeat': journey.pricePerSeat,
      'estimatedTripCost': journey.estimatedTripCost,
      'currency': journey.currency.isEmpty ? 'INR' : journey.currency.toUpperCase(),
      'jurisdictionCode': journey.jurisdictionCode.isEmpty ? 'IN' : journey.jurisdictionCode.toUpperCase(),
      'ladiesOnly': false,
      'acceptsPassengers': journey.acceptsPassengers,
      'acceptsParcels': journey.acceptsParcels,
      'acceptsShoppingRequests': journey.acceptsShoppingRequests,
    };
    final res = await apiClient.post('/trips', payload);
    final tripMap = res['trip'] as Map<String, dynamic>? ?? {};
    return Journey.fromJson(tripMap);
  }
}

class SimulatedJourneyRepository implements JourneyRepository {
  static final _now = DateTime.now();

  static final defaultSimulatedJourney = Journey(
    id: 'journey-mumbai-pune',
    origin: const ConfirmedLocation(
      displayLabel: 'Mumbai',
      formattedAddress: 'Mumbai, Maharashtra, India',
      latitude: 19.0760,
      longitude: 72.8777,
      countryCode: 'IN',
      countryName: 'India',
    ),
    destination: const ConfirmedLocation(
      displayLabel: 'Pune',
      formattedAddress: 'Pune, Maharashtra, India',
      latitude: 18.5204,
      longitude: 73.8567,
      countryCode: 'IN',
      countryName: 'India',
    ),
    timing: DateFlexibility(
      earliestDateTime: _now.add(const Duration(hours: 3)),
      latestDateTime: _now.add(const Duration(hours: 6)),
      isFlexible: true,
    ),
    travellerName: 'Susri (Verified Carrier)',
    seatCapacity: 3,
    availableSeats: 2,
    acceptsParcels: true,
    parcelCapacityTier: 'MEDIUM',
    acceptsShoppingRequests: true,
    pricePerSeat: 250.0,
    currency: 'INR',
    jurisdictionCode: 'IN',
    status: 'SCHEDULED',
    opportunities: const JourneyOpportunitySummary(
      parcelRequestsCount: 1,
      passengerRequestsCount: 1,
      shoppingRequestsCount: 1,
    ),
  );

  static final defaultOpportunities = [
    JourneyOpportunity(
      id: 'opp-parcel-1',
      type: JourneyOpportunityType.parcel,
      source: JourneyOpportunitySource.simulation,
      origin: const ConfirmedLocation(
        displayLabel: 'Bandra, Mumbai',
        formattedAddress: 'Bandra West, Mumbai, Maharashtra, India',
        latitude: 19.0596,
        longitude: 72.8295,
        countryCode: 'IN',
        countryName: 'India',
      ),
      destination: const ConfirmedLocation(
        displayLabel: 'Kothrud, Pune',
        formattedAddress: 'Kothrud, Pune, Maharashtra, India',
        latitude: 18.5074,
        longitude: 73.8077,
        countryCode: 'IN',
        countryName: 'India',
      ),
      timing: DateFlexibility(
        earliestDateTime: _now.add(const Duration(hours: 2)),
        latestDateTime: _now.add(const Duration(hours: 5)),
      ),
      rewardAmount: 350.0,
      currency: 'INR',
      weightKg: 1.5,
      requesterName: 'Aisha K.',
      pickupDistanceMeters: 450,
      dropDistanceMeters: 600,
      matchScore: CompatibilityMatchScore.greatMatch,
    ),
    JourneyOpportunity(
      id: 'opp-passenger-1',
      type: JourneyOpportunityType.passenger,
      source: JourneyOpportunitySource.simulation,
      origin: const ConfirmedLocation(
        displayLabel: 'Dadar, Mumbai',
        formattedAddress: 'Dadar TT, Mumbai, Maharashtra, India',
        latitude: 19.0178,
        longitude: 72.8478,
        countryCode: 'IN',
        countryName: 'India',
      ),
      destination: const ConfirmedLocation(
        displayLabel: 'Baner, Pune',
        formattedAddress: 'Baner, Pune, Maharashtra, India',
        latitude: 18.5590,
        longitude: 73.7868,
        countryCode: 'IN',
        countryName: 'India',
      ),
      timing: DateFlexibility(
        earliestDateTime: _now.add(const Duration(hours: 3)),
        latestDateTime: _now.add(const Duration(hours: 6)),
      ),
      rewardAmount: 250.0,
      currency: 'INR',
      seatsNeeded: 1,
      requesterName: 'Tariq M.',
      pickupDistanceMeters: 200,
      dropDistanceMeters: 350,
      matchScore: CompatibilityMatchScore.greatMatch,
    ),
    JourneyOpportunity(
      id: 'opp-shopping-1',
      type: JourneyOpportunityType.shoppingRequest,
      source: JourneyOpportunitySource.simulation,
      origin: const ConfirmedLocation(
        displayLabel: 'Phoenix Marketcity, Mumbai',
        formattedAddress: 'Kurla, Mumbai, Maharashtra, India',
        latitude: 19.0864,
        longitude: 72.8890,
        countryCode: 'IN',
        countryName: 'India',
      ),
      destination: const ConfirmedLocation(
        displayLabel: 'Viman Nagar, Pune',
        formattedAddress: 'Viman Nagar, Pune, Maharashtra, India',
        latitude: 18.5679,
        longitude: 73.9143,
        countryCode: 'IN',
        countryName: 'India',
      ),
      timing: DateFlexibility(
        earliestDateTime: _now.add(const Duration(hours: 4)),
        latestDateTime: _now.add(const Duration(hours: 7)),
      ),
      rewardAmount: 400.0,
      currency: 'INR',
      productUrl: 'https://example.com/item/handicraft-mumbai',
      requesterName: 'Fatima H.',
      pickupDistanceMeters: 800,
      dropDistanceMeters: 1100,
      matchScore: CompatibilityMatchScore.goodMatch,
    ),
  ];

  @override
  Future<List<Journey>> fetchUserJourneys() async => [defaultSimulatedJourney];

  @override
  Future<Journey> fetchJourneyDetails(String journeyId) async => defaultSimulatedJourney;

  @override
  Future<List<JourneyOpportunity>> fetchJourneyOpportunities(String journeyId) async => defaultOpportunities;

  @override
  Future<Journey> createJourney(Journey journey) async => journey;
}
