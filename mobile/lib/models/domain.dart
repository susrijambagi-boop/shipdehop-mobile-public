class TripCardModel {
  const TripCardModel({required this.id, required this.origin, required this.destination, required this.departure, required this.availableSeats, required this.price, required this.currency, required this.ladiesOnly});
  final String id, origin, destination, currency;
  final DateTime departure;
  final int availableSeats;
  final double price;
  final bool ladiesOnly;
  factory TripCardModel.fromJson(Map<String, dynamic> j) => TripCardModel(
    id: j['id']?.toString() ?? j['trip_id'].toString(), origin: j['origin_name'].toString(), destination: j['dest_name'].toString(),
    departure: DateTime.parse(j['departure_time'].toString()), availableSeats: (j['available_seats'] as num).toInt(),
    price: (j['price_per_seat'] as num).toDouble(), currency: j['currency']?.toString().trim() ?? 'INR', ladiesOnly: j['ladies_only'] as bool? ?? false,
  );
}

class MarketplaceCardModel {
  const MarketplaceCardModel({
    required this.id,
    required this.sellerId,
    required this.title,
    required this.description,
    required this.price,
    required this.currency,
    required this.category,
    required this.condition,
    required this.locationName,
    required this.jurisdictionCode,
    required this.availableQuantity,
    required this.shipEligible,
    required this.images,
  });

  final String id;
  final String sellerId;
  final String title;
  final String description;
  final double price;
  final String currency;
  final String category;
  final String condition;
  final String locationName;
  final String jurisdictionCode;
  final int availableQuantity;
  final bool shipEligible;
  final List<String> images;

  factory MarketplaceCardModel.fromJson(Map<String, dynamic> j) => MarketplaceCardModel(
        id: j['id'].toString(),
        sellerId: j['seller_id']?.toString() ?? '',
        title: j['title']?.toString() ?? 'Marketplace item',
        description: j['description']?.toString() ?? '',
        price: (j['price'] as num).toDouble(),
        currency: j['currency']?.toString().trim() ?? 'INR',
        category: j['category']?.toString() ?? 'Other',
        condition: j['condition']?.toString() ?? 'Used',
        locationName: j['location_name']?.toString() ?? 'Local listing',
        jurisdictionCode: j['jurisdiction_code']?.toString() ?? '',
        availableQuantity: (j['available_quantity'] as num?)?.toInt() ?? 1,
        shipEligible: j['ship_eligible'] as bool? ?? false,
        images: ((j['images'] as List?) ?? const <dynamic>[]).map((e) => e.toString()).where((e) => e.isNotEmpty).toList(),
      );
}

class ShipmentCardModel {
  const ShipmentCardModel({required this.id, required this.itemType, required this.pickup, required this.drop, required this.weightKg, required this.reward, required this.currency});
  final String id, itemType, pickup, drop, currency;
  final double weightKg, reward;
  factory ShipmentCardModel.fromJson(Map<String, dynamic> j) => ShipmentCardModel(
    id: j['shipment_task_id'].toString(), itemType: j['item_type'].toString(), pickup: j['pickup_name']?.toString() ?? 'Pickup',
    drop: j['drop_name']?.toString() ?? 'Drop-off', weightKg: (j['weight_kg'] as num).toDouble(), reward: (j['reward_amount'] as num).toDouble(),
    currency: j['currency']?.toString().trim() ?? 'INR',
  );
}

class TrackingPoint {
  const TrackingPoint({required this.lat, required this.lon, required this.recordedAt, this.heading, this.speedMps});
  final double lat, lon;
  final DateTime recordedAt;
  final double? heading, speedMps;
  factory TrackingPoint.fromJson(Map<String, dynamic> j) => TrackingPoint(
    lat: (j['lat'] as num).toDouble(), lon: (j['lon'] as num).toDouble(), recordedAt: DateTime.parse(j['recordedAt'].toString()),
    heading: (j['heading'] as num?)?.toDouble(), speedMps: (j['speedMps'] as num?)?.toDouble(),
  );
  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon, 'recordedAt': recordedAt.toUtc().toIso8601String(), 'heading': heading, 'speedMps': speedMps};
}

class SafeZoneModel {
  const SafeZoneModel({required this.id, required this.name, required this.address, required this.lat, required this.lon, required this.type});
  final String id, name, address, type;
  final double lat, lon;
  factory SafeZoneModel.fromJson(Map<String, dynamic> j) => SafeZoneModel(
    id: j['id'].toString(), name: j['name'].toString(), address: j['address'].toString(), type: j['type'].toString(),
    lat: (j['lat'] as num).toDouble(), lon: (j['lon'] as num).toDouble(),
  );
}
