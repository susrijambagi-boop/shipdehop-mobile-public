import 'confirmed_location.dart';
import 'date_flexibility.dart';

class RideRequest {
  final String id;
  final String requesterId;
  final ConfirmedLocation pickup;
  final ConfirmedLocation drop;
  final DateFlexibility timing;
  final int seatsNeeded;
  final String currency;
  final String jurisdictionCode;
  final String status;
  final String? matchedTripId;
  final String? matchedOrderId;

  const RideRequest({
    required this.id,
    required this.requesterId,
    required this.pickup,
    required this.drop,
    required this.timing,
    this.seatsNeeded = 1,
    this.currency = 'INR',
    this.jurisdictionCode = 'IN',
    this.status = 'OPEN',
    this.matchedTripId,
    this.matchedOrderId,
  });

  bool get isOpen => status == 'OPEN';
  bool get isMatched => status == 'MATCHED' || status == 'RESERVED';

  String get displayTitle => '${pickup.displayLabel} → ${drop.displayLabel}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'requester_id': requesterId,
        'pickup_name': pickup.displayLabel,
        'pickup': {'lat': pickup.latitude, 'lon': pickup.longitude},
        'drop_name': drop.displayLabel,
        'drop': {'lat': drop.latitude, 'lon': drop.longitude},
        'earliest_departure': timing.earliestDateTime.toIso8601String(),
        'latest_departure': timing.latestDateTime.toIso8601String(),
        'seats_needed': seatsNeeded,
        'currency': currency,
        'jurisdiction_code': jurisdictionCode,
        'status': status,
      };

  factory RideRequest.fromJson(Map<String, dynamic> json) {
    final earliest = DateTime.tryParse(json['earliest_departure']?.toString() ?? '') ?? DateTime.now();
    final latest = DateTime.tryParse(json['latest_departure']?.toString() ?? '') ?? earliest.add(const Duration(hours: 4));

    return RideRequest(
      id: json['id']?.toString() ?? 'req-1',
      requesterId: json['requester_id']?.toString() ?? '',
      pickup: ConfirmedLocation(
        displayLabel: json['pickup_name']?.toString() ?? 'Pickup',
        formattedAddress: json['pickup_name']?.toString() ?? 'Pickup Location',
        latitude: (json['pickup_lat'] as num?)?.toDouble() ?? 25.28,
        longitude: (json['pickup_lon'] as num?)?.toDouble() ?? 51.53,
      ),
      drop: ConfirmedLocation(
        displayLabel: json['drop_name']?.toString() ?? 'Dropoff',
        formattedAddress: json['drop_name']?.toString() ?? 'Dropoff Location',
        latitude: (json['drop_lat'] as num?)?.toDouble() ?? 25.41,
        longitude: (json['drop_lon'] as num?)?.toDouble() ?? 51.53,
      ),
      timing: DateFlexibility(
        earliestDateTime: earliest,
        latestDateTime: latest,
      ),
      seatsNeeded: (json['seats_needed'] as num?)?.toInt() ?? 1,
      currency: json['currency']?.toString() ?? 'INR',
      jurisdictionCode: json['jurisdiction_code']?.toString() ?? 'IN',
      status: json['status']?.toString() ?? 'OPEN',
      matchedTripId: json['matched_trip_id']?.toString(),
      matchedOrderId: json['matched_order_id']?.toString(),
    );
  }
}
