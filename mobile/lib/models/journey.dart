import 'confirmed_location.dart';
import 'date_flexibility.dart';
import 'route_result.dart';

class JourneyOpportunitySummary {
  const JourneyOpportunitySummary({
    this.parcelRequestsCount = 0,
    this.passengerRequestsCount = 0,
    this.poolerRequestsCount = 0,
    this.shoppingRequestsCount = 0,
    this.shopsterRequestsCount = 0,
  });

  final int parcelRequestsCount;
  final int passengerRequestsCount;
  final int poolerRequestsCount;
  final int shoppingRequestsCount;
  final int shopsterRequestsCount;

  int get effectivePassengerCount => passengerRequestsCount > 0 ? passengerRequestsCount : poolerRequestsCount;
  int get effectiveShoppingCount => shoppingRequestsCount > 0 ? shoppingRequestsCount : shopsterRequestsCount;

  int get totalOpportunities => parcelRequestsCount + effectivePassengerCount + effectiveShoppingCount;

  String get formattedSummary {
    if (totalOpportunities == 0) {
      return 'No active opportunities along corridor';
    }
    final parts = <String>[];
    if (parcelRequestsCount > 0) parts.add('$parcelRequestsCount Parcel${parcelRequestsCount > 1 ? 's' : ''}');
    if (effectivePassengerCount > 0) {
      final label = poolerRequestsCount > 0 ? 'Pooler' : 'Passenger';
      parts.add('$effectivePassengerCount $label${effectivePassengerCount > 1 ? 's' : ''}');
    }
    if (effectiveShoppingCount > 0) parts.add('$effectiveShoppingCount Shopping');
    return parts.join(' • ');
  }
}

class Journey {
  const Journey({
    required this.id,
    required this.origin,
    required this.destination,
    required this.timing,
    this.route,
    required this.travellerName,
    this.seatCapacity = 2,
    this.availableSeats = 2,
    bool? acceptsPassengers,
    this.acceptsParcels = true,
    this.parcelCapacityTier = 'MEDIUM',
    int? parcelCapacityUnitsTotal,
    int? parcelCapacityUnitsAvailable,
    this.acceptsShoppingRequests = false,
    this.pricePerSeat = 0.0,
    this.estimatedTripCost = 0.0,
    this.currency = 'INR',
    this.jurisdictionCode = 'IN',
    this.status = 'SCHEDULED',
    this.opportunities = const JourneyOpportunitySummary(),
  })  : acceptsPassengers = acceptsPassengers ?? (seatCapacity > 0),
        parcelCapacityUnitsTotal = parcelCapacityUnitsTotal ??
            (parcelCapacityTier == 'NONE'
                ? 0
                : parcelCapacityTier == 'ENVELOPE'
                    ? 2
                    : parcelCapacityTier == 'MEDIUM'
                        ? 6
                        : 12),
        parcelCapacityUnitsAvailable = parcelCapacityUnitsAvailable ??
            (parcelCapacityTier == 'NONE'
                ? 0
                : parcelCapacityTier == 'ENVELOPE'
                    ? 2
                    : parcelCapacityTier == 'MEDIUM'
                        ? 6
                        : 12);

  final String id;
  final ConfirmedLocation origin;
  final ConfirmedLocation destination;
  final DateFlexibility timing;
  final RouteResult? route;
  final String travellerName;
  final int seatCapacity;
  final int availableSeats;
  final bool acceptsPassengers;
  final bool acceptsParcels;
  final String parcelCapacityTier;
  final int parcelCapacityUnitsTotal;
  final int parcelCapacityUnitsAvailable;
  final bool acceptsShoppingRequests;
  final double pricePerSeat;
  final double estimatedTripCost;
  final String currency;
  final String jurisdictionCode;
  final String status;
  final JourneyOpportunitySummary opportunities;

  String get displayTitle => '${origin.displayLabel} → ${destination.displayLabel}';

  String get parcelSpaceStatusLabel {
    if (parcelCapacityTier == 'NONE' || parcelCapacityUnitsTotal == 0) return 'No parcel space';
    if (parcelCapacityUnitsAvailable <= 0) return 'Full';
    if (parcelCapacityUnitsAvailable <= (parcelCapacityUnitsTotal / 2)) return 'Limited';
    return 'Available';
  }

  String get parcelCapacityFormattedSummary {
    if (parcelCapacityTier == 'NONE' || parcelCapacityUnitsTotal == 0) return 'No parcel space configured';
    final tierLabel = parcelCapacityTier == 'ENVELOPE'
        ? 'Small items'
        : parcelCapacityTier == 'MEDIUM'
            ? 'Medium capacity'
            : 'Large luggage';
    return '$tierLabel • $parcelCapacityUnitsAvailable of $parcelCapacityUnitsTotal units available';
  }

  String get statusLabel {
    switch (status.toUpperCase()) {
      case 'SCHEDULED':
      case 'PLANNED':
        return 'Open for matches';
      case 'IN_PROGRESS':
        return 'In progress';
      case 'COMPLETED':
        return 'Completed';
      case 'CANCELLED':
        return 'Cancelled';
      default:
        return 'Open for matches';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        'timing': timing.toJson(),
        'route': route?.toJson(),
        'travellerName': travellerName,
        'seatCapacity': seatCapacity,
        'availableSeats': availableSeats,
        'acceptsPassengers': acceptsPassengers,
        'acceptsParcels': acceptsParcels,
        'parcelCapacityTier': parcelCapacityTier,
        'parcelCapacityUnitsTotal': parcelCapacityUnitsTotal,
        'parcelCapacityUnitsAvailable': parcelCapacityUnitsAvailable,
        'acceptsShoppingRequests': acceptsShoppingRequests,
        'pricePerSeat': pricePerSeat,
        'estimatedTripCost': estimatedTripCost,
        'currency': currency,
        'jurisdictionCode': jurisdictionCode,
        'status': status,
      };

  factory Journey.fromJson(Map<String, dynamic> json) {
    final tier = (json['parcelCapacityTier'] ?? json['parcel_capacity_tier']) as String? ?? 'MEDIUM';
    final defaultTotal = tier == 'NONE' ? 0 : tier == 'ENVELOPE' ? 2 : tier == 'MEDIUM' ? 6 : 12;
    final seats = ((json['seatCapacity'] ?? json['seat_capacity'] ?? json['seats']) as num?)?.toInt() ?? 2;
    return Journey(
      id: json['id'] as String? ?? 'journey-1',
      origin: ConfirmedLocation.fromJson((json['origin'] as Map<String, dynamic>?) ?? {
        'displayLabel': json['origin_name'] ?? json['originName'],
        'lat': json['origin_lat'] ?? json['originLat'],
        'lon': json['origin_lon'] ?? json['originLon'],
      }),
      destination: ConfirmedLocation.fromJson((json['destination'] as Map<String, dynamic>?) ?? {
        'displayLabel': json['destination_name'] ?? json['destinationName'],
        'lat': json['destination_lat'] ?? json['destinationLat'],
        'lon': json['destination_lon'] ?? json['destinationLon'],
      }),
      timing: DateFlexibility.fromJson((json['timing'] as Map<String, dynamic>?) ?? {
        'departureTime': json['departure_time'] ?? json['departureTime'],
      }),
      route: json['route'] != null ? RouteResult.fromJson(json['route'] as Map<String, dynamic>) : null,
      travellerName: json['travellerName'] as String? ?? json['traveller_name'] as String? ?? 'Verified Traveller',
      seatCapacity: seats,
      availableSeats: ((json['availableSeats'] ?? json['available_seats']) as num?)?.toInt() ?? seats,
      acceptsPassengers: (json['acceptsPassengers'] ?? json['accepts_passengers']) as bool? ?? (seats > 0),
      acceptsParcels: (json['acceptsParcels'] ?? json['accepts_parcels']) as bool? ?? (tier != 'NONE'),
      parcelCapacityTier: tier,
      parcelCapacityUnitsTotal: ((json['parcelCapacityUnitsTotal'] ?? json['parcel_capacity_units_total']) as num?)?.toInt() ?? defaultTotal,
      parcelCapacityUnitsAvailable: ((json['parcelCapacityUnitsAvailable'] ?? json['parcel_capacity_units_available']) as num?)?.toInt() ?? defaultTotal,
      acceptsShoppingRequests: (json['acceptsShoppingRequests'] ?? json['accepts_shopping_requests']) as bool? ?? false,
      pricePerSeat: ((json['pricePerSeat'] ?? json['price_per_seat']) as num?)?.toDouble() ?? 0.0,
      estimatedTripCost: ((json['estimatedTripCost'] ?? json['estimated_trip_cost']) as num?)?.toDouble() ?? 0.0,
      currency: (json['currency'] as String?) ?? 'INR',
      jurisdictionCode: ((json['jurisdictionCode'] ?? json['jurisdiction_code']) as String?) ?? 'IN',
      status: (json['status'] as String?) ?? 'SCHEDULED',
    );
  }
}
